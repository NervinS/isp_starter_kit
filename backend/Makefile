SHELL := /bin/bash

# ===== Defaults =====
API_BASE ?= http://localhost:3000
KEY ?= superdev

DB_HOST ?= 127.0.0.1
DB_PORT ?= 5432
DB_USER ?= ispuser
DB_NAME ?= ispdb
DB_PASS ?= isppass

SQL_FILE ?= script/bootstrap_db_v2.sql
MIGRATION_FILE_ORDENES ?= script/migration_20251001_ventas_ordenes.sql
MIGRATION_FILE_EVIDENCIAS ?= script/migration_20251001_ventas_evidencias.sql
SEED_MIN ?= 0

.PHONY: up down bootstrap smoke-min smoke-all dev-local logs smoke-agenda smoke-traslado ci smoke-ins-equipos

up:
	@docker compose up -d

down:
	@docker compose down

bootstrap:
	@echo "🔧 Parámetros:"; \
	echo "  DB_HOST=$(DB_HOST)"; \
	echo "  DB_PORT=$(DB_PORT)"; \
	echo "  DB_USER=$(DB_USER)"; \
	echo "  DB_NAME=$(DB_NAME)"; \
	echo "  SQL_FILE=$(SQL_FILE)"; \
	echo "  MIGRATION_FILE_ORDENES=$(MIGRATION_FILE_ORDENES)"; \
	echo "  MIGRATION_FILE_EVIDENCIAS=$(MIGRATION_FILE_EVIDENCIAS)"; \
	echo "  SEED_MIN=$(SEED_MIN)"; \
	API_BASE=$(API_BASE) KEY=$(KEY) DB_HOST=$(DB_HOST) DB_PORT=$(DB_PORT) DB_USER=$(DB_USER) DB_NAME=$(DB_NAME) DB_PASS="$(DB_PASS)" \
	bash script/bootstrap.sh

# Smokes mínimas (rápidas)
smoke-min:
	@API_BASE=$(API_BASE) KEY=$(KEY) ./script/smoke_inventario_min.sh && \
	API_BASE=$(API_BASE) KEY=$(KEY) ./script/smoke_kardex_min.sh && \
	API_BASE=$(API_BASE) KEY=$(KEY) ./script/smoke_tecnicos_min.sh

# Smokes extendidas
smoke-all:
	@API_BASE=$(API_BASE) KEY=$(KEY) ./script/smoke.sh && \
	API_BASE=$(API_BASE) KEY=$(KEY) ./script/smoke_agenda.sh && \
	API_BASE=$(API_BASE) KEY=$(KEY) bash script/smoke_ins_equipos_cierre.sh && \
	API_BASE=$(API_BASE) KEY=$(KEY) ./script/smoke_traslado_min.sh

# Agenda verbose contra API
smoke-agenda:
	@API_BASE=$(API_BASE) KEY=$(KEY) bash script/smoke_agenda_verbose.sh

# Traslado (vía central, tolerante por defecto; usa STRICT_CENTRAL_BALANCE=1 para fallar duro)
smoke-traslado:
	@API_BASE=$(API_BASE) KEY=$(KEY) ./script/smoke_traslado_min.sh

# INS equipos (asignar/retirar/mantener)
smoke-ins-equipos:
	@API_BASE=$(API_BASE) KEY=$(KEY) bash script/smoke_ins_equipos_cierre.sh

# Dev local de la API fuera de Docker (puerto 3001)
dev-local:
	@PORT=3001 npm run start:dev

logs:
	@docker compose logs -f api db minio

# CI local: bootstrap + smokes mínimas
ci: bootstrap smoke-min
