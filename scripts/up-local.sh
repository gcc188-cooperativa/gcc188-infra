#!/usr/bin/env bash
# Sobe o sistema localmente com Podman + Compose, construindo as imagens a partir dos fontes.
# Credencial inicial local: admin@teste.com / admin.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ADMIN_EMAIL='admin@teste.com'
ADMIN_PASSWORD='admin'

"$ROOT/scripts/init-env.sh"
"$ROOT/scripts/mkcert.sh"

# No Podman rootless o postgres roda como UID 70 (mapeado para subuid) e precisa atravessar o diretório.
chmod 755 secrets
# SELinux: bind mounts de $HOME precisam do rótulo de container (o compose não adiciona ":z" nos secrets).
if command -v chcon >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null || echo Disabled)" = Enforcing ]; then
  chcon -R -t container_file_t secrets certs caddy
fi

# Força a credencial pedida para a verificação local (init-env.sh não sobrescreve segredos existentes).
umask 077
chmod u+w secrets/app.bootstrap.admin.email secrets/app.bootstrap.admin.password
printf '%s' "$ADMIN_EMAIL" > secrets/app.bootstrap.admin.email
printf '%s' "$ADMIN_PASSWORD" > secrets/app.bootstrap.admin.password
chmod 444 secrets/app.bootstrap.admin.email secrets/app.bootstrap.admin.password

# O socket da API do Podman pode ficar inalcançável após reboot/troca de sessão.
# Usa um socket existente e funcional ou inicia um serviço local, e aponta o Compose para ele.
podman_api_ok() {
  [ -S "$1" ] && curl -fsS --max-time 2 --unix-socket "$1" http://d/_ping >/dev/null 2>&1
}
if [ -z "${DOCKER_HOST:-}" ]; then
  runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  sock_ok=""
  for sock in "$runtime/podman/podman.sock" /tmp/opencode/podman.sock /run/podman/podman.sock; do
    if podman_api_ok "$sock"; then sock_ok="$sock"; break; fi
  done
  if [ -z "$sock_ok" ]; then
    sock_ok=/tmp/opencode/podman-local.sock
    rm -f "$sock_ok"
    nohup podman system service --time=0 "unix://$sock_ok" >/tmp/opencode/podman-service.log 2>&1 &
    for _ in $(seq 1 50); do
      if podman_api_ok "$sock_ok"; then break; fi
      sleep 0.2
    done
    if ! podman_api_ok "$sock_ok"; then
      echo "Não foi possível iniciar a API do Podman (veja /tmp/opencode/podman-service.log)" >&2
      exit 1
    fi
  fi
  export DOCKER_HOST="unix://$sock_ok"
fi

COMPOSE=(podman compose --env-file versions.env --env-file .env \
  -f compose.yaml -f compose.dev.yaml -f compose.local.yaml)
"${COMPOSE[@]}" up -d --build --wait --wait-timeout 600

# O administrador inicial nasce com troca de senha obrigatória; libera o acesso direto neste ambiente local.
"${COMPOSE[@]}" exec -T \
  -e PGPASSWORD="$(cat secrets/spring.datasource.password)" db \
  psql -U "$(cat secrets/spring.datasource.username)" -d "${DB_NAME:-cooperativa}" \
  -c "UPDATE usuario SET email = '$ADMIN_EMAIL', deve_trocar_senha = false WHERE email IN ('admin', '$ADMIN_EMAIL')" >/dev/null

"${COMPOSE[@]}" ps
echo "Acesse: https://localhost:8443"
echo "Login: $ADMIN_EMAIL / $ADMIN_PASSWORD"
