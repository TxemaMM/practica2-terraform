resource "local_file" "grafana_datasources" {
  filename             = "${var.config_dir}/grafana-datasources.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/grafana-datasources.yml.tftpl", {
    prometheus_host = docker_container.prometheus.name
    loki_host       = docker_container.loki.name
  })
}

resource "local_file" "grafana_dashboards_provider" {
  filename             = "${var.config_dir}/grafana-dashboards.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/grafana-dashboards.yml.tftpl", {})
}

resource "local_file" "grafana_dashboard_containers" {
  filename             = "${var.config_dir}/dashboards/containers.json"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/dashboard-containers.json.tftpl", {
    prefix      = var.prefix
    environment = var.environment
  })
}

resource "docker_image" "grafana" {
  name         = var.grafana_image
  keep_locally = true
}

resource "docker_volume" "grafana_data" {
  name = "${var.prefix}-grafana-data"
}

resource "docker_container" "grafana" {
  name    = "${var.prefix}-grafana"
  image   = docker_image.grafana.image_id
  restart = "unless-stopped"

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_ANALYTICS_REPORTING_ENABLED=false",
    "GF_ANALYTICS_CHECK_FOR_UPDATES=false",
  ]

  labels {
    label = "alerting.config_hash"
    value = local.alerting_hash
  }

  # Solo accesible desde este equipo, no desde la red
  ports {
    internal = 3000
    external = var.grafana_port
    ip       = "127.0.0.1"
  }

  volumes {
    host_path      = abspath(local_file.grafana_datasources.filename)
    container_path = "/etc/grafana/provisioning/datasources/datasources.yml"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.grafana_data.name
    container_path = "/var/lib/grafana"
  }

  volumes {
    host_path      = abspath(local_file.grafana_dashboards_provider.filename)
    container_path = "/etc/grafana/provisioning/dashboards/dashboards.yml"
    read_only      = true
  }
  volumes {
    host_path      = abspath(local_file.grafana_dashboard_containers.filename)
    container_path = "/etc/grafana/dashboards/containers.json"
    read_only      = true
  }

  # Alertas: solo si están activadas (se monta la carpeta entera)
  dynamic "volumes" {
    for_each = var.alerting_enabled ? [1] : []
    content {
      host_path      = abspath("${var.config_dir}/alerting")
      container_path = "/etc/grafana/provisioning/alerting"
      read_only      = true
    }
  }

  networks_advanced {
    name = docker_network.monitoring.name
  }

  healthcheck {
    test     = ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:3000/api/health"]
    interval = "10s"
    timeout  = "3s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 120

  depends_on = [
    local_file.alert_rules,
    local_sensitive_file.alert_contact_points,
    local_file.alert_policies,
  ]

  lifecycle {
    replace_triggered_by = [
      local_file.grafana_datasources,
      local_file.grafana_dashboards_provider,
      local_file.grafana_dashboard_containers,
    ]
  }
}