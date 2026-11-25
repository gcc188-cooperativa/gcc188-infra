#!/usr/bin/env bash
# Funções comuns. Define COMPOSE (array) conforme o ambiente: dev | prod | ci.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
compose_for() {
  local env="${1:-dev}"
  [ -f .env ] || { echo "Falta .env: execute scripts/init-env.sh" >&2; exit 1; }
  if command -v docker >/dev/null 2>&1; then
    COMPOSE=(docker compose --env-file versions.env --env-file .env -f compose.yaml)
  else
    COMPOSE=(podman compose --env-file versions.env --env-file .env -f compose.yaml)
  fi
  case "$env" in
    dev|ci) COMPOSE+=(-f compose.dev.yaml) ;;
    prod)   COMPOSE+=(-f compose.prod.yaml) ;;
    *) echo "Ambiente inválido: $env (use dev, prod ou ci)" >&2; exit 1 ;;
  esac
}
