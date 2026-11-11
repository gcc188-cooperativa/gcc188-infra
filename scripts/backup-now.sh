#!/usr/bin/env bash
# Backup imediato (fora do agendamento): scripts/backup-now.sh [dev|prod]
source "$(dirname "$0")/lib.sh"; compose_for "${1:-dev}"; "${COMPOSE[@]}" run --rm --no-deps backup backup.sh
