resource "local_file" "alert_rules" {
  count = var.alerting_enabled ? 1 : 0

  filename             = "${var.config_dir}/alerting/rules.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/alert-rules.yml.tftpl", {
    prefix       = var.prefix
    environment  = var.environment
    web_replicas = var.expected_web_replicas
  })
}

# Lleva el token del bot: fichero sensible (no se muestra en el plan)
resource "local_sensitive_file" "alert_contact_points" {
  count = var.alerting_enabled ? 1 : 0

  filename             = "${var.config_dir}/alerting/contact-points.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/alert-contact-points.yml.tftpl", {
    telegram_bot_token = var.telegram_bot_token
    telegram_chat_id   = var.telegram_chat_id
  })
}

resource "local_file" "alert_policies" {
  count = var.alerting_enabled ? 1 : 0

  filename             = "${var.config_dir}/alerting/policies.yml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/alert-policies.yml.tftpl", {})
}