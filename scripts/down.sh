#!/usr/bin/env bash
# Para o sistema preservando volumes: scripts/down.sh dev|prod
source "$(dirname "$0")/lib.sh"; compose_for "${1:-dev}"; "${COMPOSE[@]}" down
