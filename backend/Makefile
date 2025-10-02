SHELL := /bin/bash

.PHONY: up down bootstrap smoke-min smoke-all dev-local logs smoke-agenda smoke-traslado ci

up:
	@docker compose up -d

down:
	@docker compose down

bootstrap:
	@./script/bootstrap.sh

# Smokes mínimas (rápidas)
smoke-min:
	@./script/smoke_inventario_min.sh && \
	./script/smoke_kardex_min.sh && \
	./script/smoke_tecnicos_min.sh

# Smokes extendidas (incluye agenda y traslado)
smoke-all:
	@./script/smoke.sh && \
	./script/smoke_agenda.sh && \
	./script/smoke_inventario_traslado.sh

# Dev local de la API fuera de Docker (puerto 3001)
dev-local:
	@PORT=3001 npm run start:dev

logs:
	@docker compose logs -f api db minio

# Agenda verbose contra API en 3000 dentro de docker
smoke-agenda:
	@API_BASE=http://localhost:3000 bash script/smoke_agenda_verbose.sh

# Solo el smoke de traslado entre almacenes
smoke-traslado:
	@./script/smoke_inventario_traslado.sh

# Target “CI local”: bootstrap + smokes mínimas
ci: bootstrap smoke-min
