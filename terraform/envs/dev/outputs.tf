output "web_container" {
  value = module.web.names
}

output "db_container" {
  value = module.database.host
}

output "url" {
  value = "http://localhost:${var.lb_port}"
}