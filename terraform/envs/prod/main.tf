locals {
  prefix = "${var.project}-${var.environment}"
}

# Red interna: sin salida a internet ni acceso desde fuera
resource "docker_network" "backend" {
  name     = "${local.prefix}-backend"
  internal = true
}

# Red por la que entra el tráfico externo (no es internal: así se pueden publicar puertos)
resource "docker_network" "frontend" {
  name = "${local.prefix}-frontend"
}

module "loadbalancer" {
  source = "../../modules/loadbalancer"

  name          = "${local.prefix}-lb"
  network_names = [docker_network.frontend.name, docker_network.backend.name]
  backends      = module.web.names
  backend_ids   = module.web.ids
  algorithm     = var.lb_algorithm
  host_port     = var.lb_port
  config_dir    = "${path.root}/generated/nginx"

  depends_on = [module.web]
}

module "storage" {
  source = "../../modules/storage"

  name            = "${local.prefix}-minio"
  network_name    = docker_network.backend.name
  bucket          = var.minio_bucket
  root_user       = var.minio_root_user
  root_password   = var.minio_root_password
  reader_user     = var.minio_reader_user
  reader_password = var.minio_reader_password
  images_dir      = "${path.root}/../../../assets/images"
}

module "cache" {
  source = "../../modules/cache"

  name         = "${local.prefix}-cache"
  network_name = docker_network.backend.name
  password     = var.redis_password
}

module "database" {
  source = "../../modules/database"

  name          = "${local.prefix}-db"
  network_name  = docker_network.backend.name
  db_name       = var.postgres_db
  db_user       = var.postgres_user
  db_password   = var.postgres_password
  init_sql_path = "${path.root}/../../../db/init.sql"
}

module "web" {
  source = "../../modules/web"


  replicas      = var.web_replicas
  environment   = var.environment
  name          = "${local.prefix}-web"
  build_context = "${path.root}/../../../app"
  network_name  = docker_network.backend.name
  secret_key    = var.secret_key

  db_host     = module.database.host
  db_name     = var.postgres_db
  db_user     = var.postgres_user
  db_password = var.postgres_password

  minio_endpoint   = module.storage.endpoint
  minio_bucket     = var.minio_bucket
  minio_access_key = var.minio_reader_user
  minio_secret_key = var.minio_reader_password

  cache_enabled  = true
  cache_ttl      = var.cache_ttl
  redis_host     = module.cache.host
  redis_password = var.redis_password

  gunicorn_threads = 8

  depends_on = [module.database, module.storage, module.cache]
  # Servir imágenes es trabajo de espera (I/O): más hilos por instancia

}

module "monitoring" {
  source = "../../modules/monitoring"

  prefix                 = local.prefix
  environment            = var.environment
  config_dir             = "${path.root}/generated/monitoring"
  grafana_port           = var.grafana_port
  grafana_admin_user     = var.grafana_admin_user
  grafana_admin_password = var.grafana_admin_password

  alerting_enabled      = true
  expected_web_replicas = var.web_replicas
  telegram_bot_token    = var.telegram_bot_token
  telegram_chat_id      = var.telegram_chat_id
}