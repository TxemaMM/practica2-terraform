output "endpoint" {
  description = "host:puerto de MinIO dentro de la red"
  value       = "${docker_container.minio.name}:9000"

  # No se considera disponible hasta que el bucket y el usuario existen
  depends_on = [docker_container.init]
}