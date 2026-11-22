variable "name" {
  type = string
}

variable "image" {
  type    = string
  default = "nginx:1.27-alpine"
}

variable "network_names" {
  description = "Redes a las que se conecta (frontend para publicar, backend para llegar a la web)"
  type        = list(string)
}

variable "backends" {
  description = "Nombres de los contenedores web"
  type        = list(string)
}

variable "backend_ids" {
  description = "IDs de los contenedores web, para recrear nginx si estos se recrean"
  type        = list(string)
}

variable "algorithm" {
  description = "Política de reparto: round_robin o least_conn"
  type        = string
  default     = "round_robin"

  validation {
    condition     = contains(["round_robin", "least_conn"], var.algorithm)
    error_message = "algorithm debe ser round_robin o least_conn."
  }
}

variable "host_port" {
  description = "Puerto del host donde se publica el balanceador"
  type        = number
}

variable "config_dir" {
  description = "Carpeta donde se genera nginx.conf"
  type        = string
}