variable "name" {
  type = string
}

variable "network_name" {
  type = string
}

variable "image" {
  description = "Imagen MinIO (fork pgsty), con versión fijada"
  type        = string
  default     = "pgsty/minio:RELEASE.2026-08-04T00-00-00Z"
}

variable "bucket" {
  type    = string
  default = "game-images"
}

variable "root_user" {
  type = string
}

variable "root_password" {
  type      = string
  sensitive = true
}

variable "reader_user" {
  description = "Usuario que usará la web sin poder borrar estáticos"
  type        = string
}

variable "reader_password" {
  type      = string
  sensitive = true
}

variable "images_dir" {
  description = "Carpeta local con las imágenes a subir"
  type        = string
}