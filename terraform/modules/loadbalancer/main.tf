# 1. Genera el fichero de configuración a partir de la plantilla
resource "local_file" "nginx_conf" {
  filename = "${var.config_dir}/nginx.conf"
  content = templatefile("${path.module}/templates/nginx.conf.tftpl", {
    backends      = var.backends
    algorithm     = var.algorithm
    max_upload_mb = var.max_upload_mb

  })
}

resource "docker_image" "nginx" {
  name         = var.image
  keep_locally = true
}

# 2. Contenedor nginx que monta ese fichero
resource "docker_container" "lb" {
  name    = var.name
  image   = docker_image.nginx.image_id
  restart = "unless-stopped"

  ports {
    internal = 80
    external = var.host_port
  }

  volumes {
    host_path      = abspath(local_file.nginx_conf.filename)
    container_path = "/etc/nginx/conf.d/default.conf"
    read_only      = true
  }

  # Un bloque networks_advanced por cada red de la lista
  dynamic "networks_advanced" {
    for_each = var.network_names
    content {
      name = networks_advanced.value
    }
  }

  # Si cambia el contenedor de alguna web, nginx se recrea para refrescar sus IPs
  labels {
    label = "lb.backend_ids"
    value = join(",", var.backend_ids)
  }

  healthcheck {
    test     = ["CMD", "wget", "-qO-", "http://127.0.0.1/lb-health"]
    interval = "10s"
    timeout  = "3s"
    retries  = 3
  }

  wait         = true
  wait_timeout = 60

  # Si cambia la configuración generada, se recrea el contenedor
  lifecycle {
    replace_triggered_by = [local_file.nginx_conf]
  }
}