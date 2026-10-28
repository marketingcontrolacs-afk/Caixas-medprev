-- =====================================================================
-- v54 · Contas a pagar: relatório de líquidos (folha, 13º e outros pagamentos para várias pessoas)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez e não depende da ordem dos outros arquivos.
-- Pedido da Carol (28/10/2026): a conta é lançada pelo total, mas guarda a lista de quem recebe e o
-- valor líquido de cada um, lida dos recibos anexados. Formato: [{"nome": "...", "valor": 1234.56}, ...]

alter table public.contas_pagar add column if not exists liquidos jsonb;

select 'Atualização v54 (relatório de líquidos) concluída' as resultado;
