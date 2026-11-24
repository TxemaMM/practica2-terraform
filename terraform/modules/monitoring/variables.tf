variable "prefix" {
  description = "Prefijo del entorno, por ejemplo ranking-dev"
  type        = string
}

variable "environment" {
  type = string
}

variable "config_dir" {
  description = "Carpeta donde se generan los ficheros de configuración"
  type        = string
}

variable "grafana_port" {
  description = "Puerto del host donde se publica Grafana"
  type        = number
}

variable "grafana_admin_user" {
  type = string
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "retention" {
  description = "Cuánto tiempo guarda Prometheus las métricas"
  type        = string
  default     = "3d"
}

variable "cadvisor_image" {
  type    = string
  default = "ghcr.io/google/cadvisor:0.56.2"
}

variable "prometheus_image" {
  type    = string
  default = "prom/prometheus:v3.16.0"
}

variable "grafana_image" {
  type    = string
  default = "grafana/grafana:13.3.1"
}

variable "log_retention" {
  description = "Cuánto tiempo guarda Loki los logs"
  type        = string
  default     = "72h"
}

variable "loki_image" {
  type    = string
  default = "grafana/loki:3.6.22"
}

variable "alloy_image" {
  type    = string
  default = "grafana/alloy:v1.22.0"
}