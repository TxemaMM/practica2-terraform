resource "docker_image" "cadvisor" {
  name         = var.cadvisor_image
  keep_locally = true
}

resource "docker_container" "cadvisor" {
  name       = "${var.prefix}-cadvisor"
  image      = docker_image.cadvisor.image_id
  restart    = "unless-stopped"
  privileged = true

  command = [
    "--docker_only=true",            # solo contenedores Docker
    "--housekeeping_interval=10s",   # frecuencia de medición
    "--store_container_labels=false" # menos etiquetas: métricas más limpias
  ]

  devices {
    host_path = "/dev/kmsg"
  }

  # Carpetas del host en solo lectura: de aquí lee cAdvisor las estadísticas
  volumes {
    host_path      = "/"
    container_path = "/rootfs"
    read_only      = true
  }
  volumes {
    host_path      = "/var/run"
    container_path = "/var/run"
    read_only      = true
  }
  volumes {
    host_path      = "/sys"
    container_path = "/sys"
    read_only      = true
  }
  volumes {
    host_path      = "/var/lib/docker"
    container_path = "/var/lib/docker"
    read_only      = true
  }
  volumes {
    host_path      = "/dev/disk"
    container_path = "/dev/disk"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }
}