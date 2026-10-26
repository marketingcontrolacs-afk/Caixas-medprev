-- =====================================================================
-- v39 · RH › Espelho de ponto em seção própria
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v38.
-- Pedido da Carol (26/10/2026): a importação do espelho de ponto sai de dentro da Folha e vira uma seção
-- própria do RH, com acesso separado no quadro Acessos. Assim quem faz o pedido de benefícios importa o
-- ponto sem precisar da Folha. A importação continua gravando nos lançamentos da folha do mês
-- (descrição "Espelho de ponto"), que alimentam a Folha e o Pedido de benefícios do mês seguinte.
-- Quem já tinha Folha ou Pedido de benefícios ganha Espelho de ponto, para ninguém perder o que já fazia.

alter table public.acessos drop constraint if exists acessos_modulo_check;
alter table public.acessos add constraint acessos_modulo_check
  check (modulo in ('caixa','pagar','cartao','tesouraria','ferias','folha','repasse','tarefas','premio','beneficios','colab','ponto'));

insert into public.acessos(user_id, cliente_id, modulo, nivel)
select distinct on (a.user_id, a.cliente_id) a.user_id, a.cliente_id, 'ponto', a.nivel
from public.acessos a
where a.modulo in ('folha','beneficios')
order by a.user_id, a.cliente_id, (a.nivel = 'lancamento') desc
on conflict (user_id, cliente_id, modulo) do nothing;

-- Os lançamentos da folha e o cadastro dos colaboradores também servem à seção Espelho de ponto
create or replace function public.modulos_equivalentes(mod text) returns text[]
language sql immutable as
$$ select case mod when 'folha'  then array['folha','ponto','premio','beneficios','colab']
                   when 'ferias' then array['ferias','colab']
                   else array[mod] end $$;

-- Operador Controlacs com módulos escolhidos: quem tinha Folha ou Pedido de benefícios passa a ver Espelho de ponto
update public.perfis set modulos_equipe = array_append(modulos_equipe, 'ponto')
 where modulos_equipe is not null and not ('ponto' = any(modulos_equipe))
   and (modulos_equipe && array['folha','ben']);

notify pgrst, 'reload schema';

select modulo, count(*) as acessos from public.acessos group by 1 order by 1;
