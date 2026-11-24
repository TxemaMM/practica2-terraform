.DEFAULT_GOAL := help
.PHONY: help check fmt validate plan-dev plan-prod up-dev up-prod up \
        test-dev test-prod test test-ha status urls down-dev down-prod down

TF      := terraform
ENV_DIR := terraform/envs

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
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

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

down-dev: ## Destruye dev (pide confirmación; borra sus datos)
	$(call tf,dev,destroy)

down-prod: ## Destruye prod (pide confirmación; borra sus datos)
	$(call tf,prod,destroy)

down: down-prod down-dev ## Destruye prod y dev