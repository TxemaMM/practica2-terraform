project       = "ranking"
environment   = "prod"
postgres_db   = "ranking"
postgres_user = "ranking_user"

web_replicas = 3
lb_port      = 8081
lb_algorithm = "round_robin"
cache_ttl    = 60

minio_root_user   = "ranking_admin"
minio_reader_user = "ranking_reader"

grafana_port       = 3001
grafana_admin_user = "grafana_admin"