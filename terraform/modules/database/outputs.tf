output "host" {
  description = "Nombre DNS del contenedor dentro de la red"
  value       = docker_container.db.name
}