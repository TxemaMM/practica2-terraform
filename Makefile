.DEFAULT_GOAL := help
.PHONY: help check fmt validate plan-dev plan-prod up-dev up-prod up \
        test-dev test-prod test test-ha status urls images querys \
        alerts alert-cpu alert-mem alert-replicas down-dev down-prod down

TF      := terraform
ENV_DIR := terraform/envs
ENTORNO ?= dev

# $(call tf,ENTORNO,ARGUMENTOS): ejecuta terraform dentro de ese entorno
define tf
cd $(ENV_DIR)/$(1) && $(TF) $(2)
endef

# $(call need_secrets,ENTORNO): aborta si falta el fichero de secretos
define need_secrets
@test -f $(ENV_DIR)/$(1)/secrets.auto.tfvars || { \
  echo "Falta $(ENV_DIR)/$(1)/secrets.auto.tfvars (ver el README: variables secretas)"; exit 1; }
endef

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-15s %s\n", $$1, $$2}'

check: ## Comprueba que docker, terraform y curl están disponibles
	@for c in docker terraform curl; do command -v $$c >/dev/null || { echo "Falta $$c"; exit 1; }; done
	@docker info >/dev/null 2>&1 || { echo "Docker no responde (¿arrancado? ¿tu usuario tiene permiso?)"; exit 1; }
	@echo "Requisitos OK"

fmt: ## Da formato a todo el código Terraform
	$(TF) fmt -recursive terraform

validate: ## Comprueba formato y sintaxis de dev y prod
	$(TF) fmt -check -recursive terraform
	$(call tf,dev,init -input=false)
	$(call tf,dev,validate)
	$(call tf,prod,init -input=false)
	$(call tf,prod,validate)

plan-dev: check ## Muestra qué cambiaría en dev
	$(call need_secrets,dev)
	$(call tf,dev,init -input=false)
	$(call tf,dev,plan)

plan-prod: check ## Muestra qué cambiaría en prod
	$(call need_secrets,prod)
	$(call tf,prod,init -input=false)
	$(call tf,prod,plan)

up-dev: check ## Despliega el entorno dev
	$(call need_secrets,dev)
	$(call tf,dev,init -input=false)
	$(call tf,dev,apply -auto-approve -input=false)

up-prod: check ## Despliega el entorno prod
	$(call need_secrets,prod)
	$(call tf,prod,init -input=false)
	$(call tf,prod,apply -auto-approve -input=false)

up: up-dev up-prod ## Despliega dev y prod

test-dev: ## Pruebas de humo en dev
	tests/smoke.sh dev

test-prod: ## Pruebas de humo en prod
	tests/smoke.sh prod

test: test-dev test-prod ## Pruebas de humo en dev y prod

test-ha: ## Prueba de alta disponibilidad en prod (para una réplica y la recupera)
	tests/smoke.sh prod --ha

status: ## Lista los contenedores del proyecto
	@docker ps -a --filter name=ranking- --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

urls: ## Muestra las URLs de la web y de Grafana
	@for e in dev prod; do \
	  echo "$$e: web     $$(cd $(ENV_DIR)/$$e && $(TF) output -raw url)"; \
	  echo "$$e: grafana $$(cd $(ENV_DIR)/$$e && $(TF) output -raw grafana_url)"; \
	done

images: ## Lista las imágenes guardadas en MinIO (dev y prod)
	@for e in dev prod; do \
	  echo "== $$e"; \
	  docker exec ranking-$$e-minio mc ls local/game-images 2>/dev/null || echo "  (MinIO de $$e no está en marcha)"; \
	done

querys: ## Muestra 5 consultas PromQL y 5 LogQL de ejemplo (ENTORNO=dev|prod)
	@bash scripts/queries.sh $(ENTORNO)

# --- Alertas (solo prod tiene alerting_enabled). Piden la contraseña de Grafana
# o la leen de GRAFANA_PASSWORD. Más detalles en scripts/alerts.sh

alerts: ## Estado de las reglas de alerta de prod
	@bash scripts/alerts.sh estado prod

alert-cpu: ## Provoca la alerta de CPU alta en prod y espera a que se resuelva
	@bash scripts/alerts.sh cpu prod

alert-mem: ## Provoca la alerta de memoria alta en prod (~1,3 GB) y espera a que se resuelva
	@bash scripts/alerts.sh mem prod

alert-replicas: ## Provoca la alerta de réplicas caídas en prod y espera a que se resuelva
	@bash scripts/alerts.sh replicas prod

down-dev: ## Destruye dev (pide confirmación; borra sus datos)
	$(call tf,dev,destroy)

down-prod: ## Destruye prod (pide confirmación; borra sus datos)
	$(call tf,prod,destroy)

down: down-prod down-dev ## Destruye prod y dev