SHELL := /bin/bash

.PHONY: up down bootstrap smoke dev-local logs smoke-agenda

up:
	docker compose up -d

down:
	docker compose down

bootstrap:
	./script/bootstrap.sh

smoke:
	./script/smoke_inventario_min.sh && \
	./script/smoke_kardex_min.sh && \
	./script/smoke_tecnicos_min.sh && \
	./script/smoke.sh

dev-local:
	# API local en 3001 para no chocar con el contenedor
	PORT=3001 npm run start:dev

logs:
	docker compose logs -f api db minio

smoke-agenda:
	API_BASE=http://localhost:3000 bash script/smoke_agenda_verbose.sh
