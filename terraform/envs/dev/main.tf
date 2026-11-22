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

  # Dev no tiene caché: la app arranca con CACHE_ENABLED=false
  cache_enabled = false

  depends_on = [module.database]
}