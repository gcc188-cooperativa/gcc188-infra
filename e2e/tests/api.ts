import { request, expect, type APIRequestContext } from '@playwright/test';

export const BASE = process.env.E2E_BASE_URL ?? 'https://localhost:8443';
export const ADMIN_EMAIL = process.env.E2E_ADMIN_EMAIL ?? 'admin@cooperativa.local';
export const ADMIN_PASSWORD = process.env.E2E_ADMIN_PASSWORD ?? '';
export const SENHA = 'senha-forte-e2e-2026';
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

/** Sessão HTTP com cookies e proteção CSRF (X-XSRF-TOKEN lido do cookie XSRF-TOKEN). */
export class Sessao {
  private constructor(public ctx: APIRequestContext) {}
  static async nova() {
    return new Sessao(await request.newContext({ baseURL: BASE, ignoreHTTPSErrors: true }));
  }
  async xsrf(): Promise<string> {
    const c = (await this.ctx.storageState()).cookies.find((k) => k.name === 'XSRF-TOKEN');
    return c?.value ?? '';
  }
  async login(email: string, senha: string) {
    return this.ctx.post('/api/v1/auth/login', { data: { email, senha } });
  }
  async enviar(metodo: 'post' | 'put' | 'patch' | 'delete', url: string, data?: unknown) {
    return this.ctx[metodo](`/api/v1${url}`, { data, headers: { 'X-XSRF-TOKEN': await this.xsrf() } });
  }
  get(url: string) { return this.ctx.get(`/api/v1${url}`); }
  async json<T = any>(r: Awaited<ReturnType<Sessao['get']>>, status = 200): Promise<T> {
    expect(r.status(), await r.text()).toBe(status);
    return r.json();
  }
  /** Entra; se a troca de senha for obrigatória (CA-15), troca e entra de novo. */
  static async entrar(email: string, senhaInicial: string, senhaFinal = SENHA) {
    let s = await Sessao.nova();
    let r = await s.login(email, senhaInicial);
    expect(r.status(), await r.text()).toBe(200);
    if ((await r.json()).deve_trocar_senha) {
      const t = await s.enviar('post', '/auth/alterar-senha', { senha_atual: senhaInicial, nova_senha: senhaFinal });
      expect(t.status(), await t.text()).toBe(204);
      s = await Sessao.nova();
      r = await s.login(email, senhaFinal);
      expect(r.status()).toBe(200);
    }
    return s;
  }
}

export async function admin() {
  if (!ADMIN_PASSWORD) throw new Error('Defina E2E_ADMIN_PASSWORD (conteúdo de secrets/app.bootstrap.admin.password)');
  // Regime normal: a senha já foi trocada para SENHA. Tenta-a primeiro para não acumular falhas de login
  // (5 falhas bloqueiam a conta por 15 min); só no primeiro uso cai para a senha inicial.
  const s = await Sessao.nova();
  const r = await s.login(ADMIN_EMAIL, SENHA);
  if (r.status() === 200) return s;
  await s.ctx.dispose();
  return Sessao.entrar(ADMIN_EMAIL, ADMIN_PASSWORD);
}

export async function criarUsuario(adm: Sessao, papel: 'FINANCEIRO') {
  const email = `${papel.toLowerCase()}-${uid()}@e2e.local`;
  const r = await adm.enviar('post', '/usuarios', { nome: `E2E ${papel}`, email, senha: 'senha-temporaria-e2e', papel });
  expect(r.status(), await r.text()).toBe(201);
  return Sessao.entrar(email, 'senha-temporaria-e2e');
}

export async function criarCooperando(adm: Sessao) {
  const n = Math.floor(Math.random() * 1e9).toString().padStart(9, '0');
  const email = `mot-${uid()}@e2e.local`;
  const r = await adm.enviar('post', '/cooperandos', {
    matricula: `E2E-${uid()}`.slice(0, 20), nome: 'Motorista E2E', cpf: cpfValido(n), data_ingresso: '2024-01-01',
    usuario: { email, senha: 'senha-temporaria-e2e' },
  });
  expect(r.status(), await r.text()).toBe(201);
  return { cooperando: await r.json(), email };
}

export async function criarCliente(adm: Sessao) {
  const email = `cli-${uid()}@e2e.local`;
  const r = await adm.enviar('post', '/clientes', {
    nome: 'Cliente E2E', documento: cnpjValido(), usuario: { email, senha: 'senha-temporaria-e2e' },
  });
  expect(r.status(), await r.text()).toBe(201);
  return { cliente: await r.json(), email };
}

function dv(base: number[], pesos: number[]) { const s = base.reduce((a, d, i) => a + d * pesos[i], 0) % 11; return s < 2 ? 0 : 11 - s; }
export function cpfValido(n9: string) {
  const b = n9.split('').map(Number); b.push(dv(b, [10, 9, 8, 7, 6, 5, 4, 3, 2])); b.push(dv(b, [11, 10, 9, 8, 7, 6, 5, 4, 3, 2]));
  return b.join('');
}
export function cnpjValido() {
  const b = Array.from({ length: 8 }, () => Math.floor(Math.random() * 10)).concat([0, 0, 0, 1]);
  b.push(dv(b, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])); b.push(dv(b, [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]));
  return b.join('');
}
