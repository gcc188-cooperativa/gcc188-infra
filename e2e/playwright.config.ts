import { defineConfig } from '@playwright/test';

// O sistema completo deve estar no ar (scripts/up.sh). TLS local: certificado do mkcert ou autoassinado.
const baseURL = process.env.E2E_BASE_URL ?? 'https://localhost:8443';

export default defineConfig({
  testDir: './tests',
  timeout: 60_000,
  retries: process.env.CI ? 1 : 0,
  workers: 1, // os testes compartilham o banco e criam usuários com e-mails únicos
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : 'list',
  use: { baseURL, ignoreHTTPSErrors: true, trace: 'retain-on-failure' },
  projects: [
    { name: 'api', testMatch: /.*\.api\.spec\.ts/ },
    { name: 'ui', testMatch: /.*\.ui\.spec\.ts/ },
  ],
});
