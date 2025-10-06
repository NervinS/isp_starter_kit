# Makefile (desde backend/)
SHELL := /bin/bash

DC := docker compose
API_BASE ?= http://localhost:3000
KEY ?= superdev

# PS: puedes exportar variables adicionales como TECH_ID, MAT_ID, etc.
export API_BASE
export KEY

.PHONY: help
help:
	@echo "Targets:"
	@echo "  up                - levanta stack"
	@echo "  down              - baja stack"
	@echo "  build             - build de imágenes"
	@echo "  logs              - logs del stack"
	@echo "  db-migrate        - aplica migración de hardening"
	@echo "  smoke             - pack básicos (script/smoke.sh)"
	@echo "  smoke-all         - orquesta todos los smokes"
	@echo "  smoke-repair      - smoke_inventory con autorreparación (doble confirmación)"
	@echo "  smoke-clean       - limpia kardex de pruebas de saldo insuficiente"
	@echo "  ci-smoke          - secuencia de CI (build+up+migrate+smoke_all)"

.PHONY: up down build logs
build:
	$(DC) -f docker-compose.yml -f docker-compose.override.yml build

up: build
	$(DC) -f docker-compose.yml -f docker-compose.override.yml up -d

down:
	$(DC) -f docker-compose.yml -f docker-compose.override.yml down -v

logs:
	$(DC) -f docker-compose.yml -f docker-compose.override.yml logs --tail=200

# --- DB ---
.PHONY: db-migrate
db-migrate:
	$(DC) -f docker-compose.yml -f docker-compose.override.yml exec -T db \
	  psql -U ispuser -d ispdb -f - < db/migrations/20251006_inventory_hardening.sql

# --- Smokes ---
.PHONY: smoke
smoke:
	bash script/smoke.sh

.PHONY: smoke-all
smoke-all:
	bash script/smoke_all.sh

.PHONY: smoke-repair
smoke-repair:
	API_BASE=$(API_BASE) API_KEY_HEADER="x-api-key: $(KEY)" \
	AUTO_REPAIR_STOCK=true AUTO_REPAIR_PREVIEW=true AUTO_REPAIR_CONFIRM=true \
	CLEAN=true DEBUG=false \
	bash script/smoke_inventory.sh

.PHONY: smoke-clean
smoke-clean:
	API_BASE=$(API_BASE) API_KEY_HEADER="x-api-key: $(KEY)" \
	CLEAN=true PSQL_TIMEOUT=0s \
	bash script/smoke_inventory.sh

# --- CI helper ---
.PHONY: ci-smoke
ci-smoke: up db-migrate
	bash script/smoke_all.sh
