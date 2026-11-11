#!/bin/sh
# Restaura o dump mais recente (ou o informado) em um PostgreSQL descartável e confere (CA-13):
#  1) contagem por tabela e soma dos pagamentos por contrato coerentes com a origem (se ela responde);
#  2) invariante RN05: soma dos brutos por contrato = valor_total.
# Uso: restore-check.sh [arquivo.dump]
set -eu
DUMP="${1:-$(ls -1t /backups/daily/*.dump 2>/dev/null | head -n1)}"
if [ -z "$DUMP" ] || [ ! -r "$DUMP" ]; then echo "ERRO: nenhum dump encontrado" >&2; exit 2; fi
SRC_USER="$(cat /run/secrets/spring.datasource.username)"; SRC_PASS="$(cat /run/secrets/spring.datasource.password)"
src() { PGPASSWORD="$SRC_PASS" psql -h "$PGHOST" -U "$SRC_USER" -d "$PGDATABASE" -At -c "$1"; }
dst() { PGPASSWORD="$RESTORE_PASSWORD" psql -h "$RESTORE_HOST" -U "$RESTORE_USER" -d "$RESTORE_DB" -At -c "$1"; }
echo "restaurando $DUMP em $RESTORE_HOST/$RESTORE_DB"
PGPASSWORD="$RESTORE_PASSWORD" pg_restore -h "$RESTORE_HOST" -U "$RESTORE_USER" -d "$RESTORE_DB" --no-owner --exit-on-error "$DUMP"
TABLES="usuario cooperando cliente contrato pagamento despesa refresh_token"
SOMA="SELECT coalesce(md5(string_agg(contrato_id || ':' || s, ',' ORDER BY contrato_id)), '') FROM (SELECT contrato_id, sum(valor_bruto) s FROM pagamento GROUP BY contrato_id) x"
rc=0
if src "SELECT 1" >/dev/null 2>&1; then
  for t in $TABLES; do
    a=$(src "SELECT count(*) FROM $t"); b=$(dst "SELECT count(*) FROM $t")
    # a origem pode ter recebido dados depois do dump; a restauração não pode ter MAIS linhas
    if [ "$b" -gt "$a" ]; then echo "FALHA: $t restaurou $b > origem $a"; rc=1; else echo "ok: $t origem=$a restaurado=$b"; fi
  done
  if [ "$(src "$SOMA")" = "$(dst "$SOMA")" ]; then echo "ok: soma dos pagamentos por contrato confere"; else echo "AVISO: soma difere da origem (dados mudaram após o dump?)"; fi
else
  echo "origem indisponível: verificando só a consistência interna do dump"
  for t in $TABLES; do echo "ok: $t restaurado=$(dst "SELECT count(*) FROM $t")"; done
fi
bad=$(dst "SELECT count(*) FROM contrato c JOIN (SELECT contrato_id, sum(valor_bruto) s FROM pagamento GROUP BY contrato_id) p ON p.contrato_id = c.id WHERE p.s <> c.valor_total")
if [ "$bad" != 0 ]; then echo "FALHA: $bad contrato(s) com soma de parcelas diferente do valor_total (RN05)"; rc=1; else echo "ok: RN05 (soma das parcelas = valor_total)"; fi
if [ "$rc" = 0 ]; then echo "RESTAURAÇÃO VÁLIDA"; else echo "RESTAURAÇÃO COM FALHAS"; fi
exit $rc
