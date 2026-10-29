-- =====================================================================
-- v66 · Lançamentos a validar (histórico importado do Bom Controle)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v59 e do histórico da MPA Palmas.
-- Pedido da Carol (29/10/2026): o que precisar de validação ou ajuste no histórico fica na Movimentação
-- financeira com um aviso. fin_movimentos.validar guarda o motivo; vazio = nada a validar.
-- O aviso sai sozinho quando o lançamento é corrigido (conta, categoria, valor, data, cliente/fornecedor ou
-- ligação da transferência) ou quando o escritório marca como validado na Movimentação financeira.

alter table public.fin_movimentos add column if not exists validar text;
create index if not exists fin_mov_validar on public.fin_movimentos (cliente_id) where validar is not null;

create or replace function public.fin_validar_limpa() returns trigger language plpgsql as
$$ begin
  if old.validar is not null and new.validar is not distinct from old.validar
     and (new.conta_id, new.categoria, new.valor, new.data, new.pessoa_nome, new.transf_id)
         is distinct from (old.conta_id, old.categoria, old.valor, old.data, old.pessoa_nome, old.transf_id) then
    new.validar := null;
  end if;
  return new;
end $$;
drop trigger if exists fin_validar_limpa on public.fin_movimentos;
create trigger fin_validar_limpa before update on public.fin_movimentos
  for each row execute function public.fin_validar_limpa();

-- MPA Palmas: o que o histórico do BC deixou para conferir
do $$ declare cli uuid := (select id from public.clientes where nome ilike 'MPA Palmas'); begin
  if cli is null then return; end if;
  -- 1. transferência do banco sem a outra ponta: o BC não informa para onde foi o dinheiro (ou de onde veio)
  update public.fin_movimentos m set validar = case when m.tipo = 'saida'
      then 'Transferência sem destino: o Bom Controle não informa para onde foi (outra conta, outra empresa do grupo ou tesouraria).'
      else 'Transferência sem origem: o Bom Controle não informa de onde veio (outra conta, outra empresa do grupo ou tesouraria).' end
    from public.fin_contas k
   where k.id = m.conta_id and m.cliente_id = cli and m.validar is null and k.espelho_tes is not true
     and m.transf_id is not null and m.tes_id is null
     and not exists (select 1 from public.fin_movimentos o where o.transf_id = m.transf_id and o.id <> m.id);
  -- 2. o próprio BC marcou como pendência
  update public.fin_movimentos m set validar = 'No Bom Controle estava como “Pendência - Verificar”: confira e escolha a categoria certa.'
   where m.cliente_id = cli and m.validar is null and m.categoria ilike 'Pendência%';
  -- 3. depósito da tesouraria no período do histórico do banco que não achou a entrada no banco
  update public.fin_movimentos m set validar = 'Depósito da tesouraria sem a entrada no banco (até 3 dias, mesmo valor): confira se caiu em outra conta ou se é transferência para outra empresa.'
    from public.fin_contas k
   where k.id = m.conta_id and k.espelho_tes and m.cliente_id = cli and m.validar is null and m.tipo = 'saida'
     and (m.descricao ilike '%dep%sit%' or m.descricao ilike 'dep %' or m.categoria ilike 'Depósito%')
     and m.data between '2024-01-02' and '2026-09-30'
     and (m.transf_id is null or not exists (select 1 from public.fin_movimentos o where o.transf_id = m.transf_id and o.id <> m.id));
end $$;

notify pgrst, 'reload schema';

select coalesce(c.nome,'—') as empresa, count(*) as lancamentos_a_validar
  from public.fin_movimentos m left join public.clientes c on c.id = m.cliente_id
 where m.validar is not null group by 1;
