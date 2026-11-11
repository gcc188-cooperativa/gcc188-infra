#!/bin/sh
# Backup lógico (pg_dump formato customizado) com retenção 7 diários, 4 semanais e 6 mensais (D37).
set -eu
: "${PGHOST:?}" "${PGDATABASE:?}"
PGUSER="$(cat /run/secrets/spring.datasource.username)"; export PGUSER
PGPASSWORD="$(cat /run/secrets/spring.datasource.password)"; export PGPASSWORD
B=/backups; STAMP="$(date +%Y%m%d-%H%M%S)"; FILE="$B/daily/cooperativa-$STAMP.dump"
mkdir -p "$B/daily" "$B/weekly" "$B/monthly"
pg_dump -Fc --no-owner -f "$FILE.tmp" && mv "$FILE.tmp" "$FILE"      # só vira backup válido ao terminar
echo "backup: $FILE ($(du -h "$FILE" | cut -f1))"
if [ "$(date +%u)" = 7 ]; then cp "$FILE" "$B/weekly/"; fi
if [ "$(date +%d)" = 01 ]; then cp "$FILE" "$B/monthly/"; fi
prune() { ls -1t "$1"/*.dump 2>/dev/null | tail -n +"$(($2 + 1))" | xargs -r rm -f; }
prune "$B/daily" 7; prune "$B/weekly" 4; prune "$B/monthly" 6
if [ -n "${BACKUP_RCLONE_REMOTE:-}" ]; then external-copy.sh "$FILE" || echo "AVISO: cópia externa falhou" >&2; fi
