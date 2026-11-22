variable "name" {
  type = string
}

variable "network_name" {
  type = string
}

variable "image" {
  type    = string
  default = "redis:7-alpine"
}

variable "password" {
  type      = string
  sensitive = true
}

variable "maxmemory" {
  description = "Memoria máxima de la caché"
  type        = string
  default     = "64mb"
}