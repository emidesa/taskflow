output "url" {
  value = "http://localhost:${var.front_port}"
}

output "health_url" {
  value = "http://localhost:${var.front_port}/health"
}

output "image_tag" {
  value = var.image_tag
}

output "containers" {
  value = [docker_container.db.name, docker_container.api.name, docker_container.front.name]
}

output "network" {
  value = docker_network.this.name
}
