#!/usr/bin/env bash
# Certificado local para https://localhost:8443. Usa mkcert se existir (autoridade confiável no navegador);
# caso contrário, gera um autoassinado com openssl (o navegador exibirá aviso; ok para CI).
source "$(dirname "$0")/lib.sh"
mkdir -p certs
if [ -f certs/localhost.pem ] && [ -f certs/localhost-key.pem ]; then echo "certs/ já existe"; exit 0; fi
if command -v mkcert >/dev/null; then
  mkcert -install
  mkcert -cert-file certs/localhost.pem -key-file certs/localhost-key.pem localhost 127.0.0.1 ::1
else
  echo "mkcert não encontrado: gerando certificado autoassinado (instale o mkcert para evitar avisos)" >&2
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout certs/localhost-key.pem -out certs/localhost.pem \
    -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
fi
chmod 644 certs/localhost.pem certs/localhost-key.pem
