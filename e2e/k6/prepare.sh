#!/usr/bin/env bash
# Prepara credenciais para o k6: troca a senha inicial do administrador e cria um usuário FINANCEIRO.
# Saída: arquivo e2e/k6/.k6.env com ADMIN_EMAIL, ADMIN_SENHA, FIN_EMAIL, FIN_SENHA.
# Uso: e2e/k6/prepare.sh [https://localhost:8443]
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE="${1:-https://localhost:8443}"; API="$BASE/api/v1"; JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
ADMIN_EMAIL="$(cat secrets/app.bootstrap.admin.email)"; INICIAL="$(cat secrets/app.bootstrap.admin.password)"
NOVA="perf-senha-forte-2026"; FIN_EMAIL="perf-fin@e2e.local"; FIN_SENHA="perf-senha-forte-2026"
post() { # url json [usar-xsrf]
  local xsrf; xsrf="$(awk '$6=="XSRF-TOKEN"{print $7}' "$JAR" | tail -1)"
  curl -sk -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' -H "X-XSRF-TOKEN: $xsrf" -w '\n%{http_code}' -X POST "$API$1" -d "$2"
}
login() { rm -f "$JAR"; curl -sk -c "$JAR" -H 'Content-Type: application/json' -o /dev/null -w '%{http_code}' -X POST "$API/auth/login" -d "{\"email\":\"$1\",\"senha\":\"$2\"}"; }
if [ "$(login "$ADMIN_EMAIL" "$NOVA")" != 200 ]; then
  [ "$(login "$ADMIN_EMAIL" "$INICIAL")" = 200 ] || { echo "login do administrador falhou" >&2; exit 1; }
  post /auth/alterar-senha "{\"senha_atual\":\"$INICIAL\",\"nova_senha\":\"$NOVA\"}" >/dev/null
  login "$ADMIN_EMAIL" "$NOVA" >/dev/null
fi
post /usuarios "{\"nome\":\"Perf Financeiro\",\"email\":\"$FIN_EMAIL\",\"senha\":\"senha-temporaria-perf\",\"papel\":\"FINANCEIRO\"}" >/dev/null || true
login "$FIN_EMAIL" "senha-temporaria-perf" >/dev/null
post /auth/alterar-senha "{\"senha_atual\":\"senha-temporaria-perf\",\"nova_senha\":\"$FIN_SENHA\"}" >/dev/null || true
[ "$(login "$FIN_EMAIL" "$FIN_SENHA")" = 200 ] || { echo "login do financeiro falhou" >&2; exit 1; }
printf 'ADMIN_EMAIL=%s\nADMIN_SENHA=%s\nFIN_EMAIL=%s\nFIN_SENHA=%s\n' "$ADMIN_EMAIL" "$NOVA" "$FIN_EMAIL" "$FIN_SENHA" > e2e/k6/.k6.env
echo "credenciais gravadas em e2e/k6/.k6.env"
