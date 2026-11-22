variable "name" {
  description = "Nombre del contenedor y de la imagen"
  type        = string
}

variable "build_context" {
  description = "Carpeta con el Dockerfile de la app"
  type        = string
}

variable "replicas" {
  description = "Número de instancias de la web"
  type        = number
  default     = 1
}

variable "environment" {
  description = "Nombre del entorno (dev/prod), se muestra en la UI"
  type        = string
}

variable "network_name" {
  type = string
}

variable "secret_key" {
  type      = string
  sensitive = true
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "cache_enabled" {
  type    = bool
  default = false
}

variable "cache_ttl" {
  type    = number
  default = 60
}

variable "redis_host" {
  type    = string
  default = ""
}

variable "redis_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "gunicorn_workers" {
  type    = number
  default = 2
}

variable "gunicorn_threads" {
  type    = number
  default = 4
}

variable "minio_endpoint" {
  type    = string
  default = ""
}

variable "minio_bucket" {
  type    = string
  default = "game-images"
}

variable "minio_access_key" {
  type    = string
  default = ""
}

variable "minio_secret_key" {
  type      = string
  default   = ""
  sensitive = true
}