-- Massa de dados para teste de backup (padrão: 10 contratos) e de desempenho (RNF-10: -v contratos=1000).
-- Requer o backend já inicializado (migrações + administrador). Uso:
--   docker compose ... exec -T db psql -U cooperativa -d cooperativa -v contratos=1000 -f - < e2e/seed.sql
-- Não é idempotente: use scripts/reset-dev.sh para recomeçar. Senhas são hashes fictícios (ninguém faz login).
\if :{?contratos}
\else
  \set contratos 10
\endif

INSERT INTO usuario (nome, email, senha_hash, papel, ativo, deve_trocar_senha, criado_em, atualizado_em)
SELECT 'Motorista ' || g, 'seedmot' || g || '@seed.local', '{noop}invalido', 'MOTORISTA', true, false, now(), now()
FROM generate_series(1, 20) g;
INSERT INTO usuario (nome, email, senha_hash, papel, ativo, deve_trocar_senha, criado_em, atualizado_em)
SELECT 'Cliente ' || g, 'seedcli' || g || '@seed.local', '{noop}invalido', 'CLIENTE', true, false, now(), now()
FROM generate_series(1, 50) g;

INSERT INTO cooperando (usuario_id, matricula, nome, cpf, telefone, data_ingresso, ativo, criado_em, atualizado_em)
SELECT u.id, 'SEED-' || lpad(g::text, 4, '0'), 'Motorista ' || g, lpad((90000000000 + g)::text, 11, '0'), '35999990000', date '2024-01-01', true, now(), now()
FROM generate_series(1, 20) g JOIN usuario u ON u.email = 'seedmot' || g || '@seed.local';

INSERT INTO cliente (usuario_id, nome, documento, telefone, email_contato, ativo, criado_em, atualizado_em)
SELECT u.id, 'Cliente ' || g, lpad((80000000000000 + g)::text, 14, '0'), '3532220000', 'seedcli' || g || '@seed.local', true, now(), now()
FROM generate_series(1, 50) g JOIN usuario u ON u.email = 'seedcli' || g || '@seed.local';

-- Contratos MENSAIS de 12 parcelas de 1.000,00 (taxa 10%): 80% ATIVO, 10% ENCERRADO, 10% CANCELADO.
WITH adm AS (SELECT min(id) AS id FROM usuario WHERE papel = 'ADMINISTRADOR'),
     co AS (SELECT id, row_number() OVER (ORDER BY id) - 1 AS n FROM cooperando WHERE matricula LIKE 'SEED-%'),
     cl AS (SELECT id, row_number() OVER (ORDER BY id) - 1 AS n FROM cliente WHERE email_contato LIKE 'seedcli%')
INSERT INTO contrato (cooperando_id, cliente_id, descricao, valor_total, modalidade, num_parcelas, dia_vencimento, data_inicio, taxa_tipo, taxa_valor,
                      status, criado_por_id, aprovado_por_id, aprovado_em, criado_em, atualizado_em)
SELECT co.id, cl.id, 'Contrato de teste ' || g, 12000.00, 'MENSAL', 12, 10, date '2026-01-01', 'PERCENTUAL', 10.00,
       CASE g % 10 WHEN 8 THEN 'ENCERRADO' WHEN 9 THEN 'CANCELADO' ELSE 'ATIVO' END,
       adm.id, adm.id, now(), now(), now()
FROM generate_series(1, :contratos) g, adm
JOIN co ON co.n = g % 20 JOIN cl ON cl.n = g % 50;

-- 12 pagamentos por contrato. ENCERRADO: todos REPASSADO. CANCELADO: todos CANCELADO.
-- ATIVO: parcelas 1 REPASSADO, 2 e 3 PAGO, demais PREVISTO.
INSERT INTO pagamento (contrato_id, numero_parcela, data_vencimento, valor_bruto, valor_taxa, valor_liquido, status, data_baixa, data_repasse, criado_em, atualizado_em)
SELECT c.id, p, (date '2026-01-10' + ((p - 1) * interval '1 month'))::date, 1000.00, 100.00, 900.00,
       st.s,
       CASE WHEN st.s IN ('PAGO', 'REPASSADO') THEN (date '2026-01-10' + ((p - 1) * interval '1 month'))::date END,
       CASE WHEN st.s = 'REPASSADO' THEN (date '2026-01-12' + ((p - 1) * interval '1 month'))::date END,
       now(), now()
FROM contrato c
CROSS JOIN generate_series(1, 12) p
CROSS JOIN LATERAL (SELECT CASE c.status
        WHEN 'ENCERRADO' THEN 'REPASSADO'
        WHEN 'CANCELADO' THEN 'CANCELADO'
        ELSE CASE WHEN p = 1 THEN 'REPASSADO' WHEN p IN (2, 3) THEN 'PAGO' ELSE 'PREVISTO' END END AS s) st
WHERE c.descricao LIKE 'Contrato de teste %';

-- Despesas: 5 por contrato (5.000 para 1.000 contratos); 80% do cooperando, 20% da cooperativa.
WITH adm AS (SELECT min(id) AS id FROM usuario WHERE papel = 'ADMINISTRADOR')
INSERT INTO despesa (origem, categoria, descricao, valor, data_despesa, cooperando_id, contrato_id, registrado_por_id, criado_em, atualizado_em)
SELECT CASE WHEN d % 5 = 0 THEN 'COOPERATIVA' ELSE 'COOPERANDO' END,
       (ARRAY['COMBUSTIVEL','PEDAGIO','MANUTENCAO','ADMINISTRATIVA','TRIBUTOS','OUTROS'])[1 + (d % 6)],
       'Despesa de teste ' || d, 100.00 + (d % 50), date '2026-01-01' + (d % 300),
       CASE WHEN d % 5 = 0 THEN NULL ELSE c.cooperando_id END,
       CASE WHEN d % 5 = 0 THEN NULL ELSE c.id END,
       adm.id, now(), now()
FROM (SELECT g AS d, (SELECT id FROM contrato WHERE descricao = 'Contrato de teste ' || ((g - 1) % :contratos + 1)) AS cid
      FROM generate_series(1, :contratos * 5) g) x
JOIN contrato c ON c.id = x.cid, adm;
