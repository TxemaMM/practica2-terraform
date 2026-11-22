resource "docker_image" "postgres" {
  name         = var.image
  keep_locally = true
}

resource "docker_volume" "data" {
  name = "${var.name}-data"
}

resource "docker_container" "db" {
  name    = var.name
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_USER=${var.db_user}",
    "POSTGRES_PASSWORD=${var.db_password}",
  ]

  networks_advanced {
    name = var.network_name
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/postgresql/data"
  }

  # Docker exige ruta absoluta en los bind mounts
  volumes {
    host_path      = abspath(var.init_sql_path)
    container_path = "/docker-entrypoint-initdb.d/init.sql"
    read_only      = true
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ${var.db_user} -d ${var.db_name}"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  # Equivalente a depends_on: condition: service_healthy
  wait         = true
  wait_timeout = 60
}