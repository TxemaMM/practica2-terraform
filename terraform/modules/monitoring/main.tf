# Red propia del stack de monitorización
resource "docker_network" "monitoring" {
  name = "${var.prefix}-monitoring"
}