resource "local_file" "prometheus_conf" {
  filename             = "${var.config_dir}/prometheus.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/prometheus.yml.tftpl", {
    prefix        = var.prefix
    environment   = var.environment
    cadvisor_host = docker_container.cadvisor.name
  })
}

resource "docker_image" "prometheus" {
  name         = var.prometheus_image
  keep_locally = true
}

resource "docker_volume" "prometheus_data" {
  name = "${var.prefix}-prometheus-data"
}

resource "docker_container" "prometheus" {
  name    = "${var.prefix}-prometheus"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=${var.retention}",
  ]

  volumes {
    host_path      = abspath(local_file.prometheus_conf.filename)
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.prometheus_data.name
    container_path = "/prometheus"
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }

  healthcheck {
    test     = ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:9090/-/ready"]
    interval = "10s"
    timeout  = "3s"
    retries  = 5
  }

  wait         = true
  wait_timeout = 90

  # Si cambia la configuración generada, se recrea el contenedor
  lifecycle {
    replace_triggered_by = [local_file.prometheus_conf]
  }
}