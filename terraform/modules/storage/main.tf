resource "docker_image" "minio" {
  name         = var.image
  keep_locally = true
}

resource "docker_volume" "data" {
  name = "${var.name}-data"
}

# 1. Servidor MinIO: sin puertos publicados, solo accesible dentro de la red
resource "docker_container" "minio" {
  name    = var.name
  image   = docker_image.minio.image_id
  restart = "unless-stopped"
  command = ["server", "/data"]

  env = [
    "MINIO_ROOT_USER=${var.root_user}",
    "MINIO_ROOT_PASSWORD=${var.root_password}",
    "MINIO_BROWSER=off", # sin consola web: se gestiona solo con mc
    "MC_HOST_local=http://${var.root_user}:${var.root_password}@127.0.0.1:9000",
  ]

  networks_advanced {
    name = var.network_name
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  healthcheck {
    test     = ["CMD", "mc", "ready", "local"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 60
}

# 2. Contenedor de inicialización: se ejecuta una vez y termina
resource "docker_container" "init" {
  name       = "${var.name}-init"
  image      = docker_image.minio.image_id
  entrypoint = ["sh", "/init/init.sh"]
  restart    = "no"
  must_run   = false
  attach     = true
  logs       = true

  env = [
    "MC_HOST_local=http://${var.root_user}:${var.root_password}@${docker_container.minio.name}:9000",
    "BUCKET=${var.bucket}",
    "READER_USER=${var.reader_user}",
    "READER_PASSWORD=${var.reader_password}",
    # Si cambian las imágenes, este valor cambia y el init se vuelve a ejecutar
    "IMAGES_HASH=${sha1(join("", [for f in sort(fileset(var.images_dir, "*")) : filesha1("${var.images_dir}/${f}")]))}",
  ]

  networks_advanced {
    name = var.network_name
  }

  volumes {
    host_path      = abspath("${path.module}/scripts/init.sh")
    container_path = "/init/init.sh"
    read_only      = true
  }

  volumes {
    host_path      = abspath(var.images_dir)
    container_path = "/images"
    read_only      = true
  }
}