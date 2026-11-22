output "names" {
  description = "Nombres de todas las réplicas (el LB los usa como backends)"
  value       = docker_container.web[*].name
}

output "ids" {
  value = docker_container.web[*].id
}