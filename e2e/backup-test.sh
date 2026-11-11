#!/usr/bin/env bash
# Teste de backup (CA-13): semeia dados, executa backup.sh e valida com restore-check.sh.
# Requer o sistema no ar (scripts/up.sh dev).
set -euo pipefail
source "$(dirname "$0")/../scripts/lib.sh"
compose_for "${1:-dev}"
USER_DB="$(cat secrets/spring.datasource.username)"; DB="$(grep -E '^DB_NAME=' .env | cut -d= -f2)"
echo "== semeando dados =="
"${COMPOSE[@]}" exec -T db psql -v ON_ERROR_STOP=1 -U "$USER_DB" -d "${DB:-cooperativa}" -v contratos=10 -f - < e2e/seed.sql
echo "== backup =="
scripts/backup-now.sh "${1:-dev}"
echo "== restauração em banco descartável =="
scripts/restore-check.sh "${1:-dev}"
