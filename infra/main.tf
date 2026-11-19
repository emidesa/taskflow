locals {
  name        = "taskflow-${var.environment}"
  db_password = coalesce(var.db_password, random_password.db.result)
}

# Sans caractères spéciaux : il finit dans DATABASE_URL
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "docker_network" "this" {
  name = local.name
}

resource "docker_volume" "pgdata" {
  name = "${local.name}-pgdata"

  lifecycle {
    ignore_changes = [labels]
  }
}

resource "docker_image" "postgres" {
  name         = "postgres:16-alpine"
  keep_locally = true
}

resource "docker_image" "api" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-api:${var.image_tag}"
  platform     = "linux/amd64"
  keep_locally = true
}

resource "docker_image" "front" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-front:${var.image_tag}"
  platform     = "linux/amd64"
  keep_locally = true
}

resource "docker_container" "db" {
  name    = "${local.name}-db"
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"
  wait    = true

  env = [
    "POSTGRES_USER=taskflow",
    "POSTGRES_PASSWORD=${local.db_password}",
    "POSTGRES_DB=taskflow",
  ]

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name    = docker_network.this.id
    aliases = ["db"]
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U taskflow -d taskflow"]
    interval = "10s"
    timeout  = "3s"
    retries  = 5
  }
}

resource "docker_container" "api" {
  name       = "${local.name}-api"
  image      = docker_image.api.image_id
  restart    = "unless-stopped"
  wait       = true
  depends_on = [docker_container.db]

  env = [
    "DATABASE_URL=postgres://taskflow:${local.db_password}@db:5432/taskflow",
    "APP_ENV=${var.environment}",
  ]

  networks_advanced {
    name    = docker_network.this.id
    aliases = ["api"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:3000/health || exit 1"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 3
    start_period = "10s"
  }
}

resource "docker_container" "front" {
  name       = "${local.name}-front"
  image      = docker_image.front.image_id
  restart    = "unless-stopped"
  depends_on = [docker_container.api]

  ports {
    internal = 80
    external = var.front_port
  }

  networks_advanced {
    name = docker_network.this.id
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/ || exit 1"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 3
    start_period = "5s"
  }
}
