# Runbook de operação

Todos os comandos partem da raiz do repositório. `COMPOSE` abaixo equivale a  
`docker compose --env-file versions.env --env-file .env -f compose.yaml -f compose.prod.yaml` (ou `compose.dev.yaml`). Os scripts em `scripts/` já montam isso.

## 1. Primeira implantação em um host (produção)

1. DNS: aponte `APP_DOMAIN` para o host; libere as portas **80 e 443** (necessárias à emissão ACME).
2. `scripts/init-env.sh` (gera `.env` e `secrets/`). Edite `.env`: `APP_DOMAIN`, `ACME_EMAIL`, `GHCR_OWNER`; mantenha `APP_AUTH_COOKIE_SECURE=true`. Defina `ADMIN_EMAIL`/`ADMIN_PASSWORD` antes de rodar o script se quiser escolher as credenciais iniciais.
3. **Teste a emissão no ambiente de homologação** do Let's Encrypt (R16): `ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory`; depois volte ao valor padrão e remova o volume `caddy_data` para reemitir.
4. Fixe `versions.env` em versões `X.Y.Z` testadas; `docker login ghcr.io` se as imagens forem privadas.
5. `scripts/up.sh prod`. Verifique `docker compose ps` (todos _healthy_) e `https://<domínio>`.
6. Entre com o administrador inicial e troque a senha (obrigatório). Apague a senha inicial de `secrets/app.bootstrap.admin.password` se desejar; ela só é usada se não houver administrador.

## 2. Atualizar versões

1. Em PR neste repositório, altere `BACKEND_VERSION`/`FRONT_VERSION` em `versions.env`; o CI roda o ponta a ponta com o novo conjunto.
2. No host: `git pull && scripts/up.sh prod` (o Compose recria só o que mudou; o Flyway migra o banco no _boot_ do backend).
3. **Antes de migrações de esquema**, faça `scripts/backup-now.sh prod`. As migrações são em dois passos (expandir/contrair), então a versão anterior continua compatível com o esquema novo — o _rollback_ é voltar `versions.env` e subir de novo.

## 3. Backup e restauração

- **Agendado:** contêiner `backup`, diário às `BACKUP_HOUR` (padrão 02h, `America/Sao_Paulo`). Retenção: 7 diários, 4 semanais, 6 mensais (volume `backups`). RPO 24 h, RTO 4 h (RNF-22).
- **Imediato:** `scripts/backup-now.sh prod`.
- **Validar (semanalmente e antes de cada release):** `scripts/restore-check.sh prod` — restaura o dump mais recente em um PostgreSQL descartável e confere contagens, soma dos pagamentos por contrato e a invariante RN05. Termina com `RESTAURAÇÃO VÁLIDA` ou falha (código ≠ 0).
- **Cópia externa (obrigatória em produção; LGPD):** os dumps contêm CPF, CNPJ, e-mail e telefone. Configure `BACKUP_RCLONE_REMOTE` (ex.: `s3:bucket/cooperativa`), as variáveis `RCLONE_CONFIG_*` no serviço `backup` e o secret `backup.passphrase` (acrescente-o ao serviço e à seção `secrets:` numa sobreposição própria). O arquivo é criptografado com AES-256 antes do envio (`backup/external-copy.sh`). Guarde a passphrase fora do host.
- **Restaurar de verdade (desastre):**
  1. `docker compose ... stop backend`.
  2. Copie o dump para o contêiner do banco e restaure em um banco vazio:  
     `docker compose ... exec -T db sh -c 'dropdb -U "$(cat /run/secrets/spring.datasource.username)" cooperativa && createdb -U "$(cat /run/secrets/spring.datasource.username)" cooperativa'`  
     `docker compose ... exec -T db pg_restore -U "$(cat /run/secrets/spring.datasource.username)" -d cooperativa --no-owner < backup.dump`
  3. `docker compose ... start backend` e valide por `GET /api/v1/auth/me` e consulta de um contrato.
  4. Recuperação em ponto no tempo (WAL) é evolução prevista para a nuvem.

## 4. Segredos

- Ficam em `secrets/` (diretório 0700, dono do host; **não versionado**). Os arquivos são 0444: o Compose (modo não-swarm) monta cada arquivo por _bind_ e o usuário do contêiner precisa lê-lo; a proteção é o diretório. Isso difere do "0400" citado no documento de design (D31) por limitação do Compose; em Swarm/Kubernetes use _secrets_ nativos.
- **Rotacionar `app.auth.jwt-secret`:** troque o arquivo e `docker compose ... up -d backend`. Invalida todas as sessões (aceitável; os usuários entram de novo).
- **Rotacionar a senha do banco:** `ALTER USER` no PostgreSQL com a nova senha, atualize `secrets/spring.datasource.password` e reinicie `backend` e `backup`.
- **Senha do administrador:** pelo sistema (troca de senha) ou, se perdida, redefina por outro administrador (`POST /usuarios/{id}/redefinicao-senha`). Não há e-mail (D22).

## 5. Logs e observabilidade

- Logs JSON na saída padrão com `correlation_id`; o proxy gera `X-Request-Id`. `docker compose logs backend | grep <correlation_id>`.
- Rotação por tamanho (`max-size: 20m`, `max-file: 5` por serviço), dimensionada para ~30 dias no volume previsto (RNF-23); ajuste se o tráfego crescer.
- **Perfil opcional:** `COMPOSE_PROFILES=local-db,observability` → Loki (retenção 720 h), Alloy e Grafana em `http://127.0.0.1:3000` (usuário `admin`, senha em `secrets/grafana.admin.password`). Acesso remoto: túnel SSH. **Risco:** o Alloy monta `/var/run/docker.sock` somente leitura para ler logs; quem controla esse contêiner enxerga todos os contêineres. Mantenha o perfil desligado se não for necessário.

## 6. Desempenho (RNF-10)

1. Suba o ambiente com os limites padrão (backend 1 CPU/1 GiB, PostgreSQL 1 GiB).
2. Semeie a massa: `docker compose ... exec -T db psql -U cooperativa -d cooperativa -v contratos=1000 -f - < e2e/seed.sql`.
3. `e2e/k6/prepare.sh`, depois `set -a; . e2e/k6/.k6.env; set +a; k6 run e2e/k6/perf.js`. O _threshold_ falha o teste se p95 exceder 800 ms (listagens), 1 s (comandos) ou 2 s (relatórios).

## 7. Caminho para a nuvem

1. **Mesma pilha em uma VPS:** `scripts/up.sh prod` com `APP_DOMAIN` e os _secrets_ do servidor.
2. **Banco gerenciado:** retire `local-db` de `COMPOSE_PROFILES`, aponte `DB_URL` para o serviço com `?sslmode=verify-full` (e o certificado da autoridade, se exigido) e ajuste os secrets de usuário/senha. O backup passa a ser do provedor; mantenha o `restore-check` na rotina do provedor.
3. **Orquestradores (Cloud Run, ECS, Kubernetes):** as imagens são OCI, configuradas por variáveis e secrets; o backend é sem estado (sessão em JWT, _refresh token_ e bloqueio de login no banco) e escala horizontalmente **com a mesma chave de JWT**. Proxy/TLS passam a ser do provedor; se proxy e aplicação ficarem em hosts distintos, use TLS interno ou mTLS.

## 8. Problemas comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| `backend` _unhealthy_ | banco indisponível, secret ausente ou imagem sem `thc` | `docker compose logs backend`; confira `secrets/` e `BP_HEALTH_CHECKER_ENABLED` |
| Certificado não emitido | DNS, portas 80/443 ou limite do Let's Encrypt | `docker compose logs proxy`; use homologação; mantenha `caddy_data` |
| Navegador não aceita o certificado local | autoassinado | instale o mkcert, apague `certs/` e rode `scripts/mkcert.sh` |
| Login retorna 401 repetidamente | conta bloqueada (5 falhas, 15 min) | aguarde ou redefina a senha como administrador |
| `depends_on ... required` inválido | Compose antigo | atualize para Compose ≥ 2.20 (recomendado ≥ 2.24) |
| Cookies não gravados em dev | `APP_AUTH_COOKIE_SECURE=true` sem TLS | acesse por `https://localhost:8443` |
