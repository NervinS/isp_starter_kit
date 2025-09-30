SHELL := /bin/bash

up:
\tdocker compose up -d

down:
\tdocker compose down

bootstrap:
\t./script/bootstrap.sh

smoke:
\t./script/smoke_inventario_min.sh && \
\t./script/smoke_kardex_min.sh && \
\t./script/smoke_tecnicos_min.sh && \
\t./script/smoke.sh

dev-local:
\t# API local en 3001 para no chocar con el contenedor
\tPORT=3001 npm run start:dev

logs:
\tdocker compose logs -f api db minio
