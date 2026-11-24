resource "local_file" "loki_conf" {
  filename             = "${var.config_dir}/loki.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/loki.yml.tftpl", {
    retention = var.log_retention
  })
}

resource "docker_image" "loki" {
  name         = var.loki_image
  keep_locally = true
}

resource "docker_volume" "loki_data" {
  name = "${var.prefix}-loki-data"
}

resource "docker_container" "loki" {
  name    = "${var.prefix}-loki"
  image   = docker_image.loki.image_id
  restart = "unless-stopped"

  command = ["-config.file=/etc/loki/loki.yml"]

  volumes {
    host_path      = abspath(local_file.loki_conf.filename)
    container_path = "/etc/loki/loki.yml"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.loki_data.name
    container_path = "/loki"
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }

  lifecycle {
    replace_triggered_by = [local_file.loki_conf]
  }
}