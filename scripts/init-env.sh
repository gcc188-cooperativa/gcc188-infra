#!/usr/bin/env bash
# Gera .env e os arquivos de secrets com valores aleatórios (não sobrescreve os existentes).
# Variáveis opcionais: ADMIN_EMAIL, ADMIN_PASSWORD (senha inicial do administrador; mínimo 12 caracteres).
source "$(dirname "$0")/lib.sh"
[ -f .env ] || { cp .env.example .env; echo "criado .env"; }
umask 077; mkdir -p secrets; chmod 700 secrets
# Compose (não-swarm) monta cada arquivo por bind: o usuário do contêiner precisa conseguir lê-lo.
# A proteção vem do diretório secrets/ (0700, só o dono do host) — por isso os arquivos são 0444.
put() { [ -f "secrets/$1" ] || { printf '%s' "$2" > "secrets/$1"; chmod 444 "secrets/$1"; echo "criado secrets/$1"; }; }
rnd() { openssl rand -base64 "$1" | tr -d '\n=/+' | cut -c1-"$2"; }
put spring.datasource.username "cooperativa"
put spring.datasource.password "$(rnd 33 32)"
put app.auth.jwt-secret "$(openssl rand -base64 48 | tr -d '\n')"
put app.bootstrap.admin.email "${ADMIN_EMAIL:-admin@cooperativa.local}"
put app.bootstrap.admin.password "${ADMIN_PASSWORD:-$(rnd 24 20)A1}"
put grafana.admin.password "$(rnd 18 16)"
echo "Administrador inicial: $(cat secrets/app.bootstrap.admin.email) (a senha está em secrets/app.bootstrap.admin.password; troca obrigatória no 1º acesso)"
