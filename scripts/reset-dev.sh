#!/usr/bin/env bash
# DESTRUTIVO: apaga contêineres e VOLUMES (banco, backups, certificados ACME) do ambiente de desenvolvimento.
source "$(dirname "$0")/lib.sh"
[ "${1:-}" = "--yes" ] || { read -r -p "Apagar banco e volumes locais? [digite 'sim'] " a; [ "$a" = sim ] || exit 1; }
compose_for dev; "${COMPOSE[@]}" --profile '*' down -v --remove-orphans
