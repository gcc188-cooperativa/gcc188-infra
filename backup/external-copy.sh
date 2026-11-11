#!/bin/sh
# Cópia externa CRIPTOGRAFADA (LGPD, RNF-25). Requer BACKUP_RCLONE_REMOTE, o remoto configurado no rclone
# (variáveis RCLONE_CONFIG_*) e a passphrase em /run/secrets/backup.passphrase.
set -eu
IN="$1"; OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
[ -r /run/secrets/backup.passphrase ] || { echo "sem /run/secrets/backup.passphrase" >&2; exit 1; }
openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:/run/secrets/backup.passphrase -in "$IN" -out "$OUT"
rclone copyto "$OUT" "$BACKUP_RCLONE_REMOTE/$(basename "$IN").enc"
