variable "ghcr_owner" {
  description = "Propriétaire des images sur ghcr.io (en minuscules)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.ghcr_owner))
    error_message = "ghcr_owner : minuscules, chiffres et tirets uniquement."
  }
}

variable "image_tag" {
  description = "Tag des images à déployer"
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^([0-9a-f]{7}|latest)$", var.image_tag))
    error_message = "image_tag : SHA court (7 caractères hexadécimaux) ou latest."
  }
}

variable "front_port" {
  description = "Port publié par le front"
  type        = number
  default     = 8081

  validation {
    condition     = var.front_port >= 1024 && var.front_port <= 65535
    error_message = "Le port doit être compris entre 1024 et 65535."
  }
}

variable "environment" {
  description = "Nom de l'environnement"
  type        = string
  default     = "staging"
}

variable "db_password" {
  description = "Mot de passe de la base (null = généré)"
  type        = string
  default     = null
  sensitive   = true
}

variable "ghcr_username" {
  description = "Utilisateur ghcr.io (null = pas d'authentification)"
  type        = string
  default     = null
}

variable "ghcr_token" {
  description = "Jeton ghcr.io"
  type        = string
  default     = null
  sensitive   = true
}
