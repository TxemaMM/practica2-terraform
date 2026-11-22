variable "name" {
  description = "Nombre del contenedor"
  type        = string
}

variable "network_name" {
  description = "Red Docker a la que se conecta"
  type        = string
}

variable "image" {
  type    = string
  default = "postgres:16-alpine"
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

variable "init_sql_path" {
  description = "Ruta al init.sql que se ejecuta al crear la BD"
  type        = string
}