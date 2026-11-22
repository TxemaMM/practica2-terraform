output "web_container" {
  value = module.web.name
}

output "db_container" {
  value = module.database.host
}
