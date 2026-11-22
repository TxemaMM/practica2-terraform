resource "docker_image" "web" {
  name = "${var.name}:latest"

  build {
    context = abspath(var.build_context)
    tag     = ["${var.name}:latest"]
  }

  # Reconstruye la imagen si cambia cualquier fichero de la app
  triggers = {
    src = sha1(join("", [
      for f in sort(fileset(var.build_context, "**")) :
      filesha1("${var.build_context}/${f}")
    ]))
  }
}

resource "docker_container" "web" {
  name    = var.name
  image   = docker_image.web.image_id
  restart = "unless-stopped"

  env = [
    "SECRET_KEY=${var.secret_key}",
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_USER=${var.db_user}",
    "POSTGRES_PASSWORD=${var.db_password}",
    "DB_HOST=${var.db_host}",
    "CACHE_ENABLED=${var.cache_enabled}",
    "CACHE_TTL=${var.cache_ttl}",
    "REDIS_HOST=${var.redis_host}",
    "REDIS_PASSWORD=${var.redis_password}",
    "GUNICORN_WORKERS=${var.gunicorn_workers}",
    "GUNICORN_THREADS=${var.gunicorn_threads}",
  ]

  networks_advanced {
    name = var.network_name
  }

  # La imagen slim no trae curl: usamos Python para llamar a /status
  healthcheck {
    test     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:5000/status', timeout=3)"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }

  wait         = true
  wait_timeout = 90
}