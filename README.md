# gcc188-infra

Ambiente executável do sistema completo da cooperativa de transportes: **Docker Compose**, proxy reverso com **TLS**, backup e restauração, testes ponta a ponta, teste de desempenho e perfil opcional de observabilidade. Não publica artefato de _runtime_: uma **tag** deste repositório significa "um conjunto de versões de imagens que passou nos testes" (`versions.env`, D05).

```text
Navegador ──HTTPS──▶ Caddy (proxy) ──/──────▶ front   (Nginx, estáticos)
                         │  └────────/api/*─▶ backend (Spring Boot, :8080; Actuator :8081 interno)
                         │                         └─JDBC─▶ PostgreSQL ◀── backup (pg_dump agendado)
 rede `edge`: proxy, front, backend      rede `internal` (sem saída): backend, db, backup
```

Somente o proxy publica portas. Banco, backup e a porta de gestão do backend não são alcançáveis de fora.

## Início rápido (desenvolvimento)

Requisitos: Docker com Compose ≥ 2.24, `openssl`; opcional: [mkcert](https://github.com/FiloSottile/mkcert) (evita aviso do navegador).

```bash
scripts/up.sh dev            # gera .env, secrets/ e certificado; sobe tudo e espera os healthchecks
# https://localhost:8443
cat secrets/app.bootstrap.admin.email secrets/app.bootstrap.admin.password   # administrador inicial (troca obrigatória no 1º acesso)
scripts/down.sh dev          # para, preservando volumes
scripts/reset-dev.sh         # DESTRUTIVO: apaga banco e volumes locais
```

Sem instalar Java nem Node (RNF-15). As imagens vêm de `ghcr.io/<GHCR_OWNER>/gcc188-{backend,front}` nas versões de `versions.env` (`edge` é provisório até existirem releases; fixe `X.Y.Z` no marco M0). Para imagens privadas: `docker login ghcr.io`.

## Estrutura

```text
compose.yaml            # serviços base (sem portas); perfis: local-db (padrão), tools, observability
compose.dev.yaml        # 127.0.0.1:8443→443, Caddyfile.dev, certificado local, perfil Spring dev, db em 127.0.0.1:5432
compose.prod.yaml       # portas 80/443, domínio e ACME obrigatórios
versions.env            # versões das imagens e do PostgreSQL/Caddy (RNF-24/26)
.env.example            # variáveis não secretas → .env
secrets/                # (não versionado) arquivos de secrets
caddy/                  # Caddyfile (prod, ACME) e Caddyfile.dev (certificado local)
backup/                 # imagem com pg_dump agendado, retenção, restore-check, cópia externa opcional
observability/          # Loki + Alloy + Grafana (perfil opcional)
e2e/                    # Playwright (API e UI), k6, seed.sql, backup-test.sh
scripts/                # up, down, init-env, mkcert, backup-now, restore-check, reset-dev
docs/runbook.md         # operação: subir, atualizar, restaurar, rotacionar segredos, nuvem
.github/workflows/      # ci, e2e (reutilizável), e2e-edge (agendado), perf, governance, release
```

## Decisões implementadas

| Tema | Implementação |
|---|---|
| Mesma origem (D28) | `/` → front, `/api/*` → backend; sem CORS. `X-Request-Id` gerado pelo proxy |
| TLS (D29) | dev: mkcert (ou autoassinado); prod: ACME automático do Caddy (`caddy_data` persistente); HSTS só em prod; proxy → apps em HTTP na rede privada; `sslmode` do banco na URL JDBC |
| Cabeçalhos | HSTS, CSP (`frame-ancestors 'none'`), `nosniff`, `Referrer-Policy`; Actuator fora do proxy |
| Endurecimento | `cap_drop: ALL`, `no-new-privileges`, `read_only`, rede `internal: true`, limites de CPU/memória (padrão do RNF-10), _logs_ com rotação (`local`, 20 MB × 5) |
| Segredos (D31) | arquivos em `secrets/` montados em `/run/secrets/` e lidos por `configtree`; nada no Git |
| Backup (D37) | `pg_dump -Fc` diário 02:00 (`America/Sao_Paulo`); 7 diários, 4 semanais, 6 mensais; cópia externa criptografada opcional; `restore-check` em banco descartável |
| Nuvem (D27) | perfil `local-db` desligável + `sslmode=verify-full`; imagens OCI sem estado (ver runbook) |

## Contrato esperado das imagens

Estes pontos precisam ser cumpridos pelos repositórios `gcc188-backend` e `gcc188-front`:

- **backend:** porta 8080 (API) e 8081 (Actuator, `management.server.port`); imagem com `BP_HEALTH_CHECKER_ENABLED=true` (binário `thc`, usado no _healthcheck_ via `THC_PORT`/`THC_PATH`); lê secrets de `/run/secrets/` por `spring.config.import=optional:configtree:/run/secrets/` com os arquivos `spring.datasource.username`, `spring.datasource.password`, `app.auth.jwt-secret`, `app.bootstrap.admin.email`, `app.bootstrap.admin.password`; variáveis `SPRING_DATASOURCE_URL`, `APP_AUTH_COOKIE_SECURE`, `APP_TIMEZONE`; sistema de arquivos somente leitura (usa `/tmp`); aplica Flyway no _boot_; _logs_ JSON na saída padrão.
- **front:** Nginx sem privilégios na **8080** servindo estáticos, `GET /healthz` e retorno a `index.html`; compatível com `read_only` + `/tmp` gravável.
- **UI sob teste (Playwright):** campos rotulados "E-mail" e "Senha", botão "Entrar", rota `/login`, link de menu "Usuários" para o administrador. Ajuste `e2e/tests/sessao.ui.spec.ts` se o front adotar outros textos.

## Testes

```bash
scripts/up.sh dev
cd e2e && npm ci && npx playwright install chromium
E2E_ADMIN_PASSWORD="$(cat ../secrets/app.bootstrap.admin.password)" npx playwright test   # projetos: api, ui
e2e/backup-test.sh dev                      # CA-13: semeia, faz backup, restaura em banco descartável e confere
e2e/k6/prepare.sh && set -a && . e2e/k6/.k6.env && set +a && k6 run e2e/k6/perf.js   # RNF-10 (semeie antes com contratos=1000)
```

| Teste | Cobre |
|---|---|
| `seguranca.api.spec.ts` | CA-11 (CSRF), CA-12 (reuso de _refresh_), CA-15, atributos dos _cookies_, 401 e mensagem única de login, cabeçalhos e Actuator não exposto |
| `fluxo.api.spec.ts` | contrato → aprovação → baixa → repasse; CA-01 a CA-07 (parcial), matriz de papéis, concorrência |
| `sessao.ui.spec.ts` | redirecionamento ao _login_, entrada, CA-10 |
| `backup-test.sh` | CA-13, RN05 sobre o dump restaurado |
| `k6/perf.js` | RNF-10: p95 de listagens 800 ms, comandos 1 s, relatórios 2 s, massa de 1.000/12.000/5.000 |

## CI

- **PR:** `lint` (yamllint, hadolint, shellcheck, `docker compose config` nos 3 ambientes, Trivy), `e2e` com as versões de `versions.env`, `backup` (CA-13), `governance` (título e _commits_).
- **Agendado (diário):** `e2e-edge` com as imagens `edge` de `develop` dos repositórios de aplicação.
- **Antes de cada release:** `perf` roda no PR de release do Release Please (ou manualmente).
- **Versão:** Release Please cria a tag `vX.Y.Z` e o `CHANGELOG.md`. Modelo de ramos: _trunk-based_ protegido (D04) — `master`, ramos curtos `feat/*` e `fix/*`, PR com revisão e verificações obrigatórias, _squash merge_. Commits: `tipo(escopo): descrição` (escopos em `commitlint.config.cjs`).

## Limites desta entrega

Nada aqui foi executado contra Docker (o ambiente de desenvolvimento deste repositório não o tinha): a sintaxe YAML, o `yamllint`, o `shellcheck`, `bash -n` e o `init-env.sh` foram verificados, mas **`docker compose config`/`up`, o `restore-check`, o `seed.sql`, os testes Playwright e o k6 precisam do primeiro _run_ real** (o CI faz isso). Os testes de API também dependem de o backend cumprir o contrato `gcc188-api-contract`.
