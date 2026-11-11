import { test, expect } from '@playwright/test';
import { admin, ADMIN_EMAIL, SENHA } from './api';

// Testes de interface. Os seletores seguem o contrato com o front (README): rótulos "E-mail" e "Senha",
// botão "Entrar". Ajuste-os se o front adotar outros textos.
test.describe('Interface', () => {
  test('rotas protegidas redirecionam ao login quando não há sessão', async ({ page }) => {
    await page.goto('/contratos');
    await expect(page).toHaveURL(/login/);
    await expect(page.getByRole('button', { name: /entrar/i })).toBeVisible();
  });

  test('login válido leva ao painel e exibe o menu do papel', async ({ page }) => {
    await admin(); // garante a senha final do administrador (troca no primeiro acesso)
    await page.goto('/login');
    await page.getByLabel(/e-mail/i).fill(ADMIN_EMAIL);
    await page.getByLabel(/senha/i).fill(SENHA);
    await page.getByRole('button', { name: /entrar/i }).click();
    await expect(page).not.toHaveURL(/login/);
    await expect(page.getByRole('link', { name: /usuários/i })).toBeVisible();
  });

  test('CA-10: token expirado e refresh falho redirecionam ao login', async ({ page, context }) => {
    await admin();
    await page.goto('/login');
    await page.getByLabel(/e-mail/i).fill(ADMIN_EMAIL);
    await page.getByLabel(/senha/i).fill(SENHA);
    await page.getByRole('button', { name: /entrar/i }).click();
    await expect(page).not.toHaveURL(/login/);
    await context.clearCookies({ name: 'ACCESS_TOKEN' });
    await context.clearCookies({ name: 'REFRESH_TOKEN' });
    await page.goto('/contratos');
    await expect(page).toHaveURL(/login/);
  });
});
