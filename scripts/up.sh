#!/usr/bin/env bash
# Sobe o sistema: scripts/up.sh dev|prod  (padrão: dev). Espera os healthchecks ficarem saudáveis.
source "$(dirname "$0")/lib.sh"
ENV="${1:-dev}"
[ -d secrets ] || "$ROOT/scripts/init-env.sh"
[ "$ENV" = prod ] || "$ROOT/scripts/mkcert.sh"
compose_for "$ENV"
"${COMPOSE[@]}" pull --ignore-buildable
"${COMPOSE[@]}" up -d --build --wait --wait-timeout 300
"${COMPOSE[@]}" ps
[ "$ENV" = prod ] && echo "Acesse: https://$(grep -E '^APP_DOMAIN=' .env | cut -d= -f2)" || echo "Acesse: https://localhost:8443"
