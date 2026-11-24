resource "local_file" "alloy_conf" {
  filename             = "${var.config_dir}/config.alloy"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/config.alloy.tftpl", {
    prefix      = var.prefix
    environment = var.environment
    loki_host   = docker_container.loki.name
  })
}

resource "docker_image" "alloy" {
  name         = var.alloy_image
  keep_locally = true
}

resource "docker_volume" "alloy_data" {
  name = "${var.prefix}-alloy-data"
}

resource "docker_container" "alloy" {
  name    = "${var.prefix}-alloy"
  image   = docker_image.alloy.image_id
  restart = "unless-stopped"
  user    = "root" # necesario para leer el socket de Docker

  command = [
    "run",
    "--server.http.listen-addr=0.0.0.0:12345",
    "--storage.path=/var/lib/alloy/data",
    "/etc/alloy/config.alloy",
  ]

  volumes {
    host_path      = abspath(local_file.alloy_conf.filename)
    container_path = "/etc/alloy/config.alloy"
    read_only      = true
  }
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.alloy_data.name
    container_path = "/var/lib/alloy/data"
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }

  lifecycle {
    replace_triggered_by = [local_file.alloy_conf]
  }
}