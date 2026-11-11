#!/bin/sh
# Executa backup.sh diariamente às BACKUP_HOUR (padrão 02h) no fuso do contêiner (America/Sao_Paulo).
set -eu
H="${BACKUP_HOUR:-02}"
echo "agendador de backup: diário às ${H}:00 (${TZ:-UTC})"
while true; do
  now=$(date +%s); next=$(date -d "$(date +%F) ${H}:00" +%s)
  if [ "$next" -le "$now" ]; then next=$((next + 86400)); fi
  sleep "$((next - now))"
  backup.sh || echo "ERRO: backup falhou" >&2
done
