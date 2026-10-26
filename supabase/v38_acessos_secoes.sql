-- =====================================================================
-- v38 · Acessos por seção do RH (Premiação, Pedido de benefícios, Colaboradores e prazos)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Pedido da Carol (26/10/2026): no quadro Acessos, liberar cada seção separadamente.
-- Antes, Premiação, Pedido de benefícios e Colaboradores e prazos vinham junto com Folha (ou Férias).
-- Quem já tinha Folha ganha as três seções, e quem tinha Férias ganha Colaboradores e prazos,
-- para ninguém perder o que já via. Depois é só tirar no quadro Acessos.
-- Os dados por trás dessas seções são os da folha e das férias: quem tem a seção consegue ler e gravar
-- o que ela usa (lançamentos da folha da empresa; cadastro dos colaboradores).

alter table public.acessos drop constraint if exists acessos_modulo_check;
alter table public.acessos add constraint acessos_modulo_check
  check (modulo in ('caixa','pagar','cartao','tesouraria','ferias','folha','repasse','tarefas','premio','beneficios','colab'));

insert into public.acessos(user_id, cliente_id, modulo, nivel)
select a.user_id, a.cliente_id, m.modulo, a.nivel
from public.acessos a
join (values ('folha','premio'),('folha','beneficios'),('folha','colab'),('ferias','colab')) as m(origem, modulo) on m.origem = a.modulo
on conflict (user_id, cliente_id, modulo) do nothing;

-- As regras dos dados da folha e das férias aceitam também as seções que dependem deles
create or replace function public.modulos_equivalentes(mod text) returns text[]
language sql immutable as
$$ select case mod when 'folha'  then array['folha','premio','beneficios','colab']
                   when 'ferias' then array['ferias','colab']
                   else array[mod] end $$;

create or replace function public.pode_ver(cli uuid, mod text) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_escritorio() or exists(select 1 from acessos where user_id = auth.uid() and cliente_id = cli
                                     and modulo = any(modulos_equivalentes(mod))) $$;

create or replace function public.pode_lancar(cli uuid, mod text) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_escritorio() or exists(select 1 from acessos where user_id = auth.uid() and cliente_id = cli
                                     and modulo = any(modulos_equivalentes(mod)) and nivel = 'lancamento') $$;

grant execute on all functions in schema public to authenticated;
notify pgrst, 'reload schema';

select modulo, count(*) as acessos from public.acessos group by 1 order by 1;
