// RNF-10 (D36): massa de 1.000 contratos, 12.000 pagamentos e 5.000 despesas (e2e/seed.sql com contratos=1000),
// 10 usuários virtuais. Metas (p95): listagens 800 ms, comandos 1 s, relatórios 2 s.
// Uso: k6 run -e BASE=https://localhost:8443 -e ADMIN_EMAIL=... -e ADMIN_SENHA=... -e FIN_EMAIL=... -e FIN_SENHA=... e2e/k6/perf.js
import http from 'k6/http';
import { check } from 'k6';
import { Trend } from 'k6/metrics';

const BASE = __ENV.BASE || 'https://localhost:8443';
const listagens = new Trend('t_listagens', true);
const comandos = new Trend('t_comandos', true);
const relatorios = new Trend('t_relatorios', true);

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    leitura: { executor: 'constant-vus', vus: 8, duration: '2m', exec: 'leitura' },
    comandos: { executor: 'per-vu-iterations', vus: 2, iterations: 50, exec: 'cmd', startTime: '5s' },
  },
  thresholds: {
    t_listagens: ['p(95)<800'],
    t_comandos: ['p(95)<1000'],
    t_relatorios: ['p(95)<2000'],
    http_req_failed: ['rate<0.01'],
  },
};

function entrar(email, senha) {
  const r = http.post(`${BASE}/api/v1/auth/login`, JSON.stringify({ email, senha }), { headers: { 'Content-Type': 'application/json' } });
  check(r, { 'login 200': (x) => x.status === 200 });
  const jar = http.cookieJar();
  return { xsrf: jar.cookiesForURL(BASE)['XSRF-TOKEN'][0] };
}

export function setup() {
  const s = entrar(__ENV.FIN_EMAIL, __ENV.FIN_SENHA);
  const r = http.get(`${BASE}/api/v1/pagamentos?status=PREVISTO&size=100&sort=data_vencimento,asc`);
  const ids = r.json('content').map((p) => p.id);
  return { ids, xsrf: s.xsrf };
}

export function leitura() {
  const s = entrar(__ENV.ADMIN_EMAIL, __ENV.ADMIN_SENHA);
  void s;
  for (const url of ['/contratos?size=20', '/pagamentos?size=20&status=PREVISTO', '/despesas?size=20', '/cooperandos?size=20', '/clientes?size=20']) {
    const r = http.get(`${BASE}/api/v1${url}`);
    listagens.add(r.timings.duration);
    check(r, { [`GET ${url}`]: (x) => x.status === 200 });
  }
  for (const url of ['/relatorios/resumo-financeiro?data_inicio=2026-01-01&data_fim=2026-12-31', '/relatorios/inadimplencia', '/painel/indicadores', '/despesas/totais']) {
    const r = http.get(`${BASE}/api/v1${url}`);
    relatorios.add(r.timings.duration);
    check(r, { [`GET ${url}`]: (x) => x.status === 200 });
  }
}

export function cmd(data) {
  if (__ITER === 0) entrar(__ENV.FIN_EMAIL, __ENV.FIN_SENHA);
  const id = data.ids[(__VU - 1) * 50 + __ITER];
  if (!id) return;
  const xsrf = http.cookieJar().cookiesForURL(BASE)['XSRF-TOKEN'][0];
  const h = { headers: { 'Content-Type': 'application/json', 'X-XSRF-TOKEN': xsrf } };
  const b = http.post(`${BASE}/api/v1/pagamentos/${id}/baixa`, JSON.stringify({ data_baixa: '2026-11-07' }), h);
  comandos.add(b.timings.duration);
  check(b, { 'baixa 200': (x) => x.status === 200 });
  const r = http.post(`${BASE}/api/v1/pagamentos/${id}/repasse`, JSON.stringify({ data_repasse: '2026-11-07' }), h);
  comandos.add(r.timings.duration);
  check(r, { 'repasse 200': (x) => x.status === 200 });
}
