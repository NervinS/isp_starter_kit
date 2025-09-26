#!/usr/bin/env bash
set -euo pipefail

docker compose exec -T db bash -lc "
set -e
TABLES=\$(psql -qAtX -U ispuser -d ispdb -c 'SELECT tablename FROM pg_tables WHERE schemaname=''public'' ORDER BY tablename;')

IFS=\$'\n'
for t in \$TABLES; do
  echo
  echo \"===== \$t (count + first 20 rows) =====\"
  psql -U ispuser -d ispdb -c \"SELECT count(*) AS total FROM public.\\\"\$t\\\";\"
  psql -U ispuser -d ispdb -c \"SELECT * FROM public.\\\"\$t\\\" LIMIT 20;\"
done
"
