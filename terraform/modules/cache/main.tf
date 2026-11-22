resource "docker_image" "redis" {
  name         = var.image
  keep_locally = true
}

resource "docker_container" "cache" {
  name    = var.name
  image   = docker_image.redis.image_id
  restart = "unless-stopped"

  env = ["REDIS_PASSWORD=${var.password}"]

  # Con maxmemory y allkeys-lru, al llenarse expulsa las claves menos usadas
  command = [
    "sh", "-c",
    "exec redis-server --requirepass \"$REDIS_PASSWORD\" --maxmemory ${var.maxmemory} --maxmemory-policy allkeys-lru"
  ]

  networks_advanced {
    name = var.network_name
  }

  healthcheck {
    test     = ["CMD-SHELL", "REDISCLI_AUTH=\"$REDIS_PASSWORD\" redis-cli ping | grep -q PONG"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 60
}