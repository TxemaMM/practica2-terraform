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

variable "web_replicas" {
  type = number
}

variable "lb_port" {
  type = number
}

variable "lb_algorithm" {
  type    = string
  default = "round_robin"
}

variable "minio_bucket" {
  type    = string
  default = "game-images"
}

variable "minio_root_user" {
  type = string
}

variable "minio_reader_user" {
  type = string
}

variable "minio_root_password" {
  type      = string
  sensitive = true
}

variable "minio_reader_password" {
  type      = string
  sensitive = true
}

variable "grafana_port" {
  type = number
}

variable "grafana_admin_user" {
  type = string
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}