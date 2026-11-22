variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "postgres_db" {
  type = string
}

variable "postgres_user" {
  type = string
}

# Secretos: vienen de secrets.auto.tfvars (fuera de git)
variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "secret_key" {
  type      = string
  sensitive = true
}
