import { test, expect } from '@playwright/test';
import { Sessao, admin, criarUsuario, criarCooperando, criarCliente, SENHA } from './api';

// Fluxo principal pelo sistema integrado (proxy → backend → banco): cadastro, contrato, aprovação,
// baixa e repasse, com checagem de papel e de escopo (CA-01, CA-03, CA-04, CA-05).
test('fluxo completo: do contrato ao repasse', async () => {
  const adm = await admin();
  const fin = await criarUsuario(adm, 'FINANCEIRO');
  const { cooperando, email: emailMot } = await criarCooperando(adm);
  const { cliente } = await criarCliente(adm);
  const mot = await Sessao.entrar(emailMot, 'senha-temporaria-e2e');

  // Motorista elabora e submete (RN12)
  const novo = await mot.enviar('post', '/contratos', {
    cooperando_id: cooperando.id, cliente_id: cliente.id, descricao: 'Transporte E2E', valor_total: 6000,
    modalidade: 'MENSAL', num_parcelas: 3, dia_vencimento: 10, data_inicio: '2026-12-01', taxa_tipo: 'PERCENTUAL', taxa_valor: 10,
  });
  expect(novo.status(), await novo.text()).toBe(201);
  const contrato = await novo.json();
  expect(contrato.status).toBe('RASCUNHO');
  expect((await mot.enviar('post', `/contratos/${contrato.id}/submissao`)).status()).toBe(200);

  // CA-05: motorista não aprova
  expect((await mot.enviar('post', `/contratos/${contrato.id}/aprovacao`)).status()).toBe(403);

  // CA-01: administrador aprova; 3 pagamentos de 2000 / 200 / 1800
  const apr = await adm.enviar('post', `/contratos/${contrato.id}/aprovacao`);
  expect(apr.status(), await apr.text()).toBe(200);
  const det = await adm.json(await adm.get(`/contratos/${contrato.id}`));
  expect(det.status).toBe('ATIVO');
  expect(det.pagamentos).toHaveLength(3);
  for (const p of det.pagamentos) {
    expect([p.valor_bruto, p.valor_taxa, p.valor_liquido]).toEqual([2000, 200, 1800]);
    expect(p.status).toBe('PREVISTO');
  }
  const pag = det.pagamentos[0];

  // CA-03: repasse de pagamento PREVISTO → 409
  const r409 = await fin.enviar('post', `/pagamentos/${pag.id}/repasse`, { data_repasse: '2026-12-12' });
  expect(r409.status()).toBe(409);
  expect((await fin.json(await fin.get(`/pagamentos/${pag.id}`))).status).toBe('PREVISTO');

  // Baixa e repasse pelo financeiro; administrador não registra baixa (matriz de permissões)
  expect((await adm.enviar('post', `/pagamentos/${pag.id}/baixa`, { data_baixa: '2026-12-10' })).status()).toBe(403);
  const baixa = await fin.json(await fin.enviar('post', `/pagamentos/${pag.id}/baixa`, { data_baixa: '2026-12-10' }));
  expect(baixa.status).toBe('PAGO');
  const rep = await fin.json(await fin.enviar('post', `/pagamentos/${pag.id}/repasse`, { data_repasse: '2026-12-12' }));
  expect(rep.status).toBe('REPASSADO');

  // CA-07: encerrar com parcelas em aberto → 409
  expect((await adm.enviar('post', `/contratos/${contrato.id}/encerramento`)).status()).toBe(409);

  // CA-04: outro motorista não enxerga o contrato (404)
  const outro = await criarCooperando(adm);
  const motB = await Sessao.entrar(outro.email, 'senha-temporaria-e2e');
  expect((await motB.get(`/contratos/${contrato.id}`)).status()).toBe(404);

  // Concorrência otimista: PUT com versão antiga → 409 (D13) — contrato ATIVO não é editável (RN12)
  const put = await adm.enviar('put', `/contratos/${contrato.id}`, { ...contrato, versao: 0 });
  expect(put.status()).toBe(409);
});

test('CA-02: taxa fixa maior que a parcela responde 422 com o campo taxa_valor', async () => {
  const adm = await admin();
  const { cooperando, email } = await criarCooperando(adm);
  const { cliente } = await criarCliente(adm);
  const mot = await Sessao.entrar(email, 'senha-temporaria-e2e');
  const c = await mot.enviar('post', '/contratos', {
    cooperando_id: cooperando.id, cliente_id: cliente.id, descricao: 'Taxa alta', valor_total: 1200, modalidade: 'MENSAL',
    num_parcelas: 3, dia_vencimento: 5, data_inicio: '2026-12-01', taxa_tipo: 'FIXO', taxa_valor: 500,
  });
  const id = (await c.json()).id;
  const r = await mot.enviar('post', `/contratos/${id}/submissao`);
  expect(r.status()).toBe(422);
  const prob = await r.json();
  expect(prob.codigo_regra).toBe('RN03');
  expect(prob.campos_invalidos.map((x: any) => x.campo)).toContain('taxa_valor');
});

test('CA-06: despesa da cooperativa com cooperando_id responde 422', async () => {
  const adm = await admin();
  const { cooperando } = await criarCooperando(adm);
  const r = await adm.enviar('post', '/despesas', {
    origem: 'COOPERATIVA', categoria: 'ADMINISTRATIVA', descricao: 'Aluguel', valor: 1000, data_despesa: '2026-11-05', cooperando_id: cooperando.id,
  });
  expect(r.status()).toBe(422);
});

test.afterAll(() => { void SENHA; });
