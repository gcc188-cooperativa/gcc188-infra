#!/usr/bin/env bash
# Restaura o dump mais recente em banco descartável e valida (CA-13): scripts/restore-check.sh [dev|prod]
source "$(dirname "$0")/lib.sh"; compose_for "${1:-dev}"
"${COMPOSE[@]}" --profile tools run --rm restore-check
"${COMPOSE[@]}" --profile tools rm -sf db-restore >/dev/null
