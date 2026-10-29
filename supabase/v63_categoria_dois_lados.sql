-- =====================================================================
-- v63 · A categoria vale para entrada e saída (como uma conta contábil)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v52.
-- Pedido da Carol (29/10/2026): o estorno de uma venda é lançado na mesma categoria da venda
-- (Recebimento de Atendimentos), e o relatório por categoria mostra o que entrou e o que saiu.
-- Por isso as categorias que só existiam para o "outro lado" ficam inativas:
--   - as com estorno ou devolução no nome (ex.: Restituições (Estorno), Devolução - Banco);
--   - as repetidas só para entrada (ex.: Pendência - Verificar (entrada)).
-- Os lançamentos que já usam essas categorias ficam marcados "Revisar categoria" (cat_revisar) para a
-- Carol escolher a categoria certa. A categoria antiga continua no lançamento até ela corrigir.

alter table public.fin_movimentos add column if not exists cat_revisar boolean not null default false;
alter table public.fin_titulos    add column if not exists cat_revisar boolean not null default false;

drop table if exists pg_temp.cat_inativar;
create temp table cat_inativar as
select categoria from public.plano_contas
 where categoria ~* '(estorno|devolu)' or categoria ~* '\(entrada\)'
union
select categoria from public.fin_plano
 where categoria ~* '(estorno|devolu)' or categoria ~* '\(entrada\)';

update public.plano_contas set ativo = false where categoria in (select categoria from cat_inativar) and ativo is distinct from false;
update public.fin_plano    set ativo = false where categoria in (select categoria from cat_inativar) and ativo is distinct from false;

update public.fin_movimentos set cat_revisar = true where categoria in (select categoria from cat_inativar) and not cat_revisar;
update public.fin_titulos    set cat_revisar = true where categoria in (select categoria from cat_inativar) and not cat_revisar;

-- o que ficou para revisar, por categoria
select 'inativada' as o_que, categoria, null::bigint as lancamentos from cat_inativar
union all
select 'a revisar', categoria, count(*) from public.fin_movimentos where cat_revisar group by categoria
order by 1, 2;
