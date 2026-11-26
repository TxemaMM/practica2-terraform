#!/usr/bin/env bash
# Pruebas de las alertas de Grafana: provoca una alerta real y muestra en
# directo cómo cambia su estado (Normal -> Pending -> Firing -> Normal).
#
# Uso: scripts/alerts.sh estado|cpu|mem|replicas [prod|dev]
#
#   estado    muestra el estado actual de todas las reglas
#   cpu       arranca un contenedor que gasta 1 núcleo de CPU (regla > 80 %)
#   mem       arranca un contenedor que reserva ~1,3 GB (regla > 1 GiB)
#   replicas  detiene <entorno>-web-1 (regla: faltan réplicas web)
#
# Pide la contraseña del admin de Grafana (o la lee de GRAFANA_PASSWORD).
set -u

ACTION="${1:-}"
ENV="${2:-prod}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TFVARS="$ROOT/terraform/envs/$ENV/terraform.tfvars"

usage() { echo "Uso: $0 estado|cpu|mem|replicas [prod|dev]"; exit 2; }
[ -f "$TFVARS" ] || usage

# Lee un valor de terraform.tfvars (igual que tests/smoke.sh)
tfvar() {
  awk -F'=' -v k="$1" '$1 ~ "^"k"[ \t]*$" {
    sub(/#.*/, "", $2); gsub(/[ \t"]/, "", $2); print $2 }' "$TFVARS"
}

PREFIX="$(tfvar project)-$ENV"
GF_PORT="$(tfvar grafana_port)"
GF_USER="$(tfvar grafana_admin_user)"
GF_URL="http://127.0.0.1:${GF_PORT}"
GF_PASS=""

WEB_IMAGE="${PREFIX}-web:latest"   # ya existe en local y trae Python
STRESS="${PREFIX}-stress"          # lleva el prefijo: cAdvisor y Prometheus lo ven
WEB1="${PREFIX}-web-1"

# Títulos de las reglas: deben coincidir con templates/alert-rules.yml.tftpl
RULE_CPU="CPU alta en contenedor"
RULE_MEM="Memoria alta en contenedor"
RULE_REP="Réplicas web caídas"

MEM_MB=1300      # algo más de 1 GiB, el umbral de la regla de memoria
MAX_WAIT=420     # segundos máximos esperando cada cambio de estado
POLL=10          # cada cuánto se consulta Grafana (igual que su evaluación)

for c in docker curl python3; do
  command -v "$c" >/dev/null || { echo "Falta $c"; exit 1; }
done

# --- Grafana -------------------------------------------------------------

ask_password() {
  if [ -n "${GRAFANA_PASSWORD:-}" ]; then
    GF_PASS="$GRAFANA_PASSWORD"
  elif [ -t 0 ]; then
    read -rsp "Contraseña de Grafana (usuario $GF_USER): " GF_PASS; echo
  else
    echo "Define GRAFANA_PASSWORD o ejecuta el script en una terminal"; exit 2
  fi
}

# Reglas de alerta en formato de la API de Prometheus que ofrece Grafana
rules_json() {
  curl -sf -m 5 -u "$GF_USER:$GF_PASS" "$GF_URL/api/prometheus/grafana/api/v1/rules" || {
    echo "No se pudo consultar Grafana en $GF_URL (¿está arrancado? ¿contraseña correcta?)" >&2
    return 1
  }
}

# Sin argumento: "nombre<TAB>estado" de cada regla. Con argumento: el estado de esa regla.
STATE_PY='
import json, sys
want = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
norm = {"normal": "inactive", "alerting": "firing"}
found = False
for group in data.get("data", {}).get("groups", []):
    for rule in group.get("rules", []):
        name = rule.get("name", "")
        state = str(rule.get("state", "?")).lower()
        state = norm.get(state, state)
        if not want:
            print(name + "\t" + state)
        elif name == want:
            print(state)
            found = True
if want and not found:
    print("missing")
'

rule_state() { rules_json | python3 -c "$STATE_PY" "$1"; }

pretty() {
  case "$1" in
    inactive)   echo "Normal" ;;
    pending)    echo "Pending (se cumple, esperando el tiempo «for»)" ;;
    firing)     echo "FIRING 🔴 (aviso enviado a Telegram)" ;;
    recovering) echo "Recovering (volviendo a la normalidad)" ;;
    missing)    echo "no existe" ;;
    *)          echo "$1" ;;
  esac
}

# Comprueba la contraseña y que la regla existe
check_rule() {
  local st
  st="$(rule_state "$1")" || exit 1
  if [ "$st" = "missing" ]; then
    echo "No existe la regla «$1» en $ENV."
    echo "En este proyecto las alertas solo están activadas en prod (alerting_enabled = true)."
    exit 1
  fi
  [ "$st" = "inactive" ] || echo "Aviso: la regla ya está en estado $(pretty "$st")."
}

# Espera a que la regla llegue al estado indicado e imprime cada cambio
wait_state() {
  local rule="$1" want="$2" start=$SECONDS last="" st beat=30
  while :; do
    st="$(rule_state "$rule")" || return 1
    if [ "$st" != "$last" ]; then
      printf '  [%3ss] %s\n' "$((SECONDS - start))" "$(pretty "$st")"
      last="$st"; beat=$((SECONDS - start + 30))
    elif [ $((SECONDS - start)) -ge "$beat" ]; then
      printf '  [%3ss] … sigue en %s\n' "$((SECONDS - start))" "$(pretty "$st")"
      beat=$((beat + 30))
    fi
    [ "$st" = "$want" ] && return 0
    if [ $((SECONDS - start)) -ge "$MAX_WAIT" ]; then
      echo "  Tiempo agotado ($MAX_WAIT s) esperando el estado $want"; return 1
    fi
    sleep "$POLL"
  done
}

# --- Limpieza: pase lo que pase, no deja el entorno roto -----------------

RESTART_WEB=0
cleanup() {
  if docker inspect "$STRESS" >/dev/null 2>&1; then
    docker rm -f "$STRESS" >/dev/null 2>&1 && echo "  (contenedor $STRESS eliminado)"
  fi
  if [ "$RESTART_WEB" = 1 ]; then
    docker start "$WEB1" >/dev/null 2>&1 && echo "  ($WEB1 arrancada de nuevo)"
  fi
}
trap cleanup EXIT
trap 'echo; echo "Interrumpido"; exit 130' INT TERM

# --- Contenedor de estrés ------------------------------------------------

start_stress() {
  docker image inspect "$WEB_IMAGE" >/dev/null 2>&1 ||
    { echo "No existe la imagen $WEB_IMAGE: despliega antes el entorno (make up-$ENV)"; exit 1; }
  docker rm -f "$STRESS" >/dev/null 2>&1

  # --network none: no puede hablar con nada. Termina solo tras MAX_WAIT s.
  case "$1" in
    cpu)
      docker run -d --rm --name "$STRESS" --network none --cpus 1 \
        --label practica2.stress=cpu "$WEB_IMAGE" python -c "
import time
end = time.time() + $MAX_WAIT
while time.time() < end:
    pass
" >/dev/null ;;
    mem)
      docker run -d --rm --name "$STRESS" --network none --memory "$((MEM_MB + 300))m" \
        --label practica2.stress=mem "$WEB_IMAGE" python -c "
import time
data = b'x' * ($MEM_MB * 1024 * 1024)
time.sleep($MAX_WAIT)
" >/dev/null ;;
  esac || { echo "No se pudo arrancar $STRESS"; exit 1; }
}

stress_test() {   # stress_test cpu|mem "Título de la regla" "descripción"
  local kind="$1" rule="$2" desc="$3"
  ask_password
  check_rule "$rule"

  if [ "$kind" = "mem" ]; then
    local avail
    avail="$(awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo)"
    if [ "$avail" -lt $((MEM_MB + 500)) ]; then
      echo "Memoria libre insuficiente: ${avail} MB (hacen falta unos $((MEM_MB + 500)) MB)"; exit 1
    fi
  fi

  echo "== Alerta «$rule» en $ENV"
  echo "Se arranca $STRESS: $desc"
  start_stress "$kind"
  echo "Esperando a que la alerta salte (suele tardar 2-3 minutos)..."
  wait_state "$rule" firing || exit 1
  echo "🔴 Alerta disparada: revisa Telegram y Alerting → Alert rules en $GF_URL"

  docker rm -f "$STRESS" >/dev/null 2>&1
  echo "Contenedor de estrés detenido. Esperando a que se resuelva..."
  wait_state "$rule" inactive || exit 1
  echo "✅ Alerta resuelta: debería llegarte el aviso de RESUELTA"
}

replicas_test() {
  ask_password
  check_rule "$RULE_REP"
  echo "== Alerta «$RULE_REP» en $ENV"
  echo "Se detiene $WEB1 (la web sigue funcionando con el resto de réplicas)"
  docker stop "$WEB1" >/dev/null || exit 1
  RESTART_WEB=1
  echo "Esperando a que la alerta salte (suele tardar 1-2 minutos)..."
  wait_state "$RULE_REP" firing || exit 1
  echo "🔴 Alerta disparada: revisa Telegram"

  docker start "$WEB1" >/dev/null && RESTART_WEB=0
  echo "$WEB1 arrancada de nuevo. Esperando a que se resuelva..."
  wait_state "$RULE_REP" inactive || exit 1
  echo "✅ Alerta resuelta"
}

show_states() {
  ask_password
  local out
  out="$(rules_json | python3 -c "$STATE_PY")" || exit 1
  echo "== Reglas de alerta en $ENV ($GF_URL)"
  if [ -z "$out" ]; then
    echo "  No hay reglas (en este proyecto solo prod tiene alertas)"; return
  fi
  while IFS=$'\t' read -r name state; do
    printf '  • %s → %s\n' "$name" "$(pretty "$state")"
  done <<< "$out"
}

case "$ACTION" in
  estado)   show_states ;;
  cpu)      stress_test cpu "$RULE_CPU" "un bucle que gasta 1 núcleo de CPU" ;;
  mem)      stress_test mem "$RULE_MEM" "reserva ${MEM_MB} MB de memoria" ;;
  replicas) replicas_test ;;
  *)        usage ;;
esac
