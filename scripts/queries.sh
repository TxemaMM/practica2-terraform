#!/usr/bin/env bash
# Muestra 5 consultas PromQL (Prometheus) y 5 LogQL (Loki) de ejemplo,
# ya preparadas para el entorno, con lo que hay que mirar en cada una.
# Uso: scripts/queries.sh [dev|prod]
set -u

ENV="${1:-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TFVARS="$ROOT/terraform/envs/$ENV/terraform.tfvars"
[ -f "$TFVARS" ] || { echo "Uso: $0 [dev|prod]"; exit 2; }

# Lee un valor de terraform.tfvars (igual que tests/smoke.sh)
tfvar() {
  awk -F'=' -v k="$1" '$1 ~ "^"k"[ \t]*$" {
    sub(/#.*/, "", $2); gsub(/[ \t"]/, "", $2); print $2 }' "$TFVARS"
}

P="$(tfvar project)-$ENV"          # prefijo: ranking-dev / ranking-prod
GF_PORT="$(tfvar grafana_port)"

# Colores solo si la salida es una terminal
if [ -t 1 ]; then
  B=$'\e[1m'; Y=$'\e[33m'; C=$'\e[36m'; M=$'\e[35m'; D=$'\e[2m'; R=$'\e[0m'
else
  B=""; Y=""; C=""; M=""; D=""; R=""
fi

q() {   # q número "título" "consulta" "qué ver"
  printf '\n%s%s. %s%s\n' "$B" "$1" "$2" "$R"
  printf '   %s%s%s\n' "$Y" "$3" "$R"
  printf '   %sQué ver:%s %s\n' "$D" "$R" "$4"
}

cat <<EOF
${B}Consultas de ejemplo para ${ENV}${R}
Dónde: Grafana http://localhost:${GF_PORT} → Explore → elige el origen de datos
       (Prometheus o Loki) → modo "Code" → pega la consulta → Run query
EOF

# --- Prometheus ------------------------------------------------------------
printf '\n%s══════════ PROMETHEUS · PromQL (métricas: números en el tiempo) ══════════%s\n' "$C$B" "$R"

q "P1" "¿Prometheus está recogiendo datos?" \
  'up' \
  "una serie por cada objetivo (job \"prometheus\" y job \"cadvisor\"). 1 = responde, 0 = caído. Es la consulta más simple: el nombre de una métrica."

q "P2" "Memoria de cada réplica web (filtro por etiqueta)" \
  "container_memory_working_set_bytes{name=~\"${P}-web-.*\"}" \
  "una línea por réplica web. Lo de las llaves filtra por etiqueta y =~ admite expresiones regulares. Es un gauge: el valor de ahora, en bytes (85000000 ≈ 85 MB)."

q "P3" "% de CPU por contenedor (counter + rate + sum)" \
  "sum by (name) (rate(container_cpu_usage_seconds_total{name=~\"${P}-.*\"}[1m])) * 100" \
  "el uso de CPU de cada contenedor, en %. La métrica es un counter (solo sube), así que rate(...[1m]) calcula su ritmo por segundo en el último minuto. sum by (name) junta una línea por contenedor. Normalmente sale casi 0; con 'make alert-cpu' el de estrés sube a ~100."

q "P4" "Los 3 contenedores que más memoria usan" \
  "topk(3, container_memory_working_set_bytes{name=~\"${P}-.*\"})" \
  "solo los 3 contenedores con más memoria en cada momento. topk ordena y se queda con los primeros. Suelen salir Grafana, Prometheus o Loki, no la web."

q "P5" "¿Cuántas réplicas web están vivas? (la misma lógica que la alerta)" \
  "count((time() - container_last_seen{name=~\"${P}-web-.*\"}) < 30)" \
  "el número de réplicas web vistas en los últimos 30 s ($(tfvar web_replicas) en ${ENV}). time() - container_last_seen son los segundos desde que cAdvisor vio cada una. Detén una con 'docker stop ${P}-web-1' y verás bajar el número en menos de un minuto."

# --- Loki ------------------------------------------------------------------
printf '\n%s══════════ LOKI · LogQL (logs: líneas de texto) ══════════%s\n' "$M$B" "$R"

q "L1" "Todos los logs del entorno (selector de etiquetas)" \
  "{environment=\"${ENV}\"}" \
  "las líneas de todos los contenedores de ${ENV}, las más nuevas primero. Lo de las llaves elige los logs por etiqueta (las pone Alloy). Despliega una línea para ver su etiqueta 'container'."

q "L2" "Los logs de un solo contenedor" \
  "{container=\"${P}-web-1\"}" \
  "solo web-1: los accesos de gunicorn. Las líneas con 'Python-urllib' son su healthcheck (cada 10 s) y las de '/status' son el navegador refrescando los indicadores."

q "L3" "Quitar el ruido: solo las visitas reales" \
  "{container=~\"${P}-web-.*\"} != \"/status\" != \"Python-urllib\"" \
  "las peticiones de verdad (GET /, POST /login, votos, /images/...) de todas las réplicas. != descarta las líneas que contienen ese texto. Navega por la web y verás aparecer tus clics, cada uno en la réplica que lo atendió."

q "L4" "Buscar errores" \
  "{environment=\"${ENV}\"} |= \"ERROR\"" \
  "solo las líneas que contienen 'ERROR'. |= filtra por texto (distingue mayúsculas; para no distinguirlas usa |~ \"(?i)error\"). Detén MinIO con 'docker stop ${P}-minio', recarga la web y aparecerá 'MinIO no disponible'."

q "L5" "Contar peticiones por réplica (logs convertidos en números)" \
  "sum by (container) (count_over_time({container=~\"${P}-web-.*\"} |= \"HTTP/1\" != \"Python-urllib\" [5m]))" \
  "cuántas peticiones (sin healthchecks) ha atendido cada réplica en los últimos 5 min. count_over_time cuenta las líneas, así que saca un número de los logs. Con round-robin las cifras deberían salir muy parecidas: es el reparto del balanceador visto desde los logs."

printf '\n%sPara el otro entorno: make querys ENTORNO=%s%s\n' "$D" "$([ "$ENV" = dev ] && echo prod || echo dev)" "$R"
