#!/usr/bin/env bash
# Pruebas de humo de un entorno ya desplegado.
# Uso: tests/smoke.sh dev|prod [--ha]
set -u

ENV="${1:-}"
HA="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TFVARS="$ROOT/terraform/envs/$ENV/terraform.tfvars"
[ -f "$TFVARS" ] || { echo "Uso: $0 dev|prod [--ha]"; exit 2; }

# Lee un valor de terraform.tfvars (así los puertos y réplicas no se repiten aquí)
tfvar() {
  awk -F'=' -v k="$1" '$1 ~ "^"k"[ \t]*$" {
    sub(/#.*/, "", $2); gsub(/[ \t"]/, "", $2); print $2 }' "$TFVARS"
}

PREFIX="$(tfvar project)-$ENV"
LB_PORT="$(tfvar lb_port)"
GRAFANA_PORT="$(tfvar grafana_port)"
REPLICAS="$(tfvar web_replicas)"
BASE="http://localhost:${LB_PORT}"

# prod tiene caché Redis; dev no la tiene
if [ "$ENV" = "prod" ]; then CACHE="up"; else CACHE="disabled"; fi

PASS=0; FAIL=0
check() {                 # check "descripción" comando [args...]
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✔ $desc"; PASS=$((PASS + 1))
  else
    echo "  ✘ $desc"; FAIL=$((FAIL + 1))
  fi
}

http_code() { curl -s -o /dev/null -m 5 -w '%{http_code}' "$1"; }
served_by() {
  curl -s -o /dev/null -m 5 -D - "$BASE/" | tr -d '\r' |
    awk -F': ' 'tolower($1)=="x-served-by" {print $2}'
}

# --- Comprobaciones ---------------------------------------------------
c_containers() { [ "$(docker ps --filter "name=${PREFIX}-web-" -q | wc -l)" -eq "$REPLICAS" ]; }
c_unhealthy()  { [ -z "$(docker ps --filter "name=${PREFIX}-" --filter health=unhealthy -q)" ]; }
c_lb()         { [ "$(http_code "$BASE/lb-health")" = "200" ]; }
c_status() {
  local body; body="$(curl -s -m 5 "$BASE/status")"
  echo "$body" | grep -q '"status":"ok"' && echo "$body" | grep -q "\"cache\":\"$CACHE\""
}
c_balance() {
  local n; n="$(for _ in $(seq 1 $((REPLICAS * 4))); do served_by; done | sort -u | wc -l)"
  [ "$n" -eq "$REPLICAS" ]
}
c_image() { [ "$(curl -s -o /dev/null -m 5 -w '%{http_code} %{content_type}' "$BASE/images/1")" = "200 image/jpeg" ]; }
c_grafana() { curl -s -m 5 "http://127.0.0.1:${GRAFANA_PORT}/api/health" | grep -q -E '"database": *"ok"'; }
c_all_ok() {
  for _ in $(seq 1 10); do [ "$(http_code "$BASE/")" = "200" ] || return 1; done
}
c_recovered() {
  for _ in $(seq 1 30); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' "${PREFIX}-web-1")" = "healthy" ] && return 0
    sleep 2
  done
  return 1
}

echo "== Entorno: $ENV ($REPLICAS réplicas web, balanceador en :$LB_PORT)"
check "Hay $REPLICAS contenedores web en marcha"        c_containers
check "Ningún contenedor del entorno está unhealthy"    c_unhealthy
check "El balanceador responde (/lb-health)"            c_lb
check "/status: base de datos arriba y caché = $CACHE"  c_status
check "El reparto llega a las $REPLICAS réplicas"       c_balance
check "Las imágenes se sirven desde MinIO"              c_image
check "Grafana responde en :$GRAFANA_PORT"              c_grafana

if [ "$HA" = "--ha" ]; then
  echo "== Alta disponibilidad: se detiene ${PREFIX}-web-1"
  docker stop "${PREFIX}-web-1" >/dev/null
  check "10 peticiones seguidas devuelven 200 con una réplica caída" c_all_ok
  docker start "${PREFIX}-web-1" >/dev/null
  check "La réplica detenida vuelve a estar healthy"    c_recovered
fi

echo "== Resultado: $PASS correctas, $FAIL fallidas"
[ "$FAIL" -eq 0 ]