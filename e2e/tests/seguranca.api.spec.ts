import { test, expect } from '@playwright/test';
import { Sessao, admin, ADMIN_EMAIL } from './api';

test.describe('Autenticação, CSRF e cabeçalhos', () => {
  test('CA-11: POST sem X-XSRF-TOKEN responde 403 e nada é alterado', async () => {
    const adm = await admin();
    const r = await adm.ctx.post('/api/v1/usuarios', { data: { nome: 'X', email: 'x@e2e.local', senha: 'senha-temporaria-e2e', papel: 'FINANCEIRO' } });
    expect(r.status()).toBe(403);
    const lista = await adm.json(await adm.get('/usuarios?size=100'));
    expect(lista.content.some((u: any) => u.email === 'x@e2e.local')).toBe(false);
  });

  test('401 sem cookies e mensagem única de falha de login', async () => {
    const s = await Sessao.nova();
    expect((await s.get('/contratos')).status()).toBe(401);
    const a = await s.login('inexistente@e2e.local', 'qualquer-senha-123');
    const b = await s.login(ADMIN_EMAIL, 'senha-errada-123456');
    expect(a.status()).toBe(401);
    expect(b.status()).toBe(401);
    expect((await a.json()).detail).toBe((await b.json()).detail);
  });

  test('cookies de token são HttpOnly, Secure e SameSite=Strict; XSRF-TOKEN é legível', async () => {
    const adm = await admin();
    const cookies = (await adm.ctx.storageState()).cookies;
    const acesso = cookies.find((c) => c.name === 'ACCESS_TOKEN')!;
    const refresh = cookies.find((c) => c.name === 'REFRESH_TOKEN')!;
    const xsrf = cookies.find((c) => c.name === 'XSRF-TOKEN')!;
    for (const c of [acesso, refresh]) { expect(c.httpOnly).toBe(true); expect(c.secure).toBe(true); expect(c.sameSite).toBe('Strict'); }
    expect(xsrf.httpOnly).toBe(false);
  });

  test('CA-12: refresh token reutilizado responde 401 e revoga a família', async () => {
    const adm = await admin();
    const refreshAntigo = (await adm.ctx.storageState()).cookies.find((c) => c.name === 'REFRESH_TOKEN')!.value;
    expect((await adm.ctx.post('/api/v1/auth/refresh')).status()).toBe(200); // rotaciona
    const atacante = await Sessao.nova();
    await atacante.ctx.storageState(); // contexto limpo
    const r = await atacante.ctx.post('/api/v1/auth/refresh', { headers: { Cookie: `REFRESH_TOKEN=${refreshAntigo}` } });
    expect(r.status()).toBe(401);
    // a família inteira foi revogada: o refresh atual do usuário legítimo também falha
    expect((await adm.ctx.post('/api/v1/auth/refresh')).status()).toBe(401);
  });

  test('cabeçalhos de segurança no proxy e Actuator não exposto', async ({ request }) => {
    const r = await request.get('/');
    expect(r.headers()['x-content-type-options']).toBe('nosniff');
    expect(r.headers()['content-security-policy']).toContain("frame-ancestors 'none'");
    expect((await request.get('/actuator/health')).status()).not.toBe(200);
    expect((await request.get('/api/actuator/health')).status()).not.toBe(200);
  });

  test('CA-15: usuário com troca de senha pendente só acessa troca de senha e logout', async () => {
    const adm = await admin();
    const email = `pendente-${Date.now()}@e2e.local`;
    const c = await adm.enviar('post', '/usuarios', { nome: 'Pendente', email, senha: 'senha-temporaria-e2e', papel: 'FINANCEIRO' });
    expect(c.status()).toBe(201);
    const s = await Sessao.nova();
    expect((await s.login(email, 'senha-temporaria-e2e')).status()).toBe(200);
    const r = await s.get('/contratos');
    expect(r.status()).toBe(403);
  });
});
