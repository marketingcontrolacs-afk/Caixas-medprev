-- =====================================================================
-- v51 · Luana (Oliveira Biguaçu): ajuda de custo fixa de R$ 150, sem a regra do sábado
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): a Luana tem ajuda de custo fixa de R$ 150,00 e o sábado não vale para ela.
-- Marca "Sábado não conta", tira o valor de sábado que a importação do ponto gravou (R$ 50, contrato antigo),
-- apaga os sábados lançados para ela nas folhas abertas e, se ela ainda não tem ajuda fixa no mês, grava R$ 150.
create or replace function pg_temp.sem_acento(t text) returns text language sql immutable as
$$ select lower(translate(coalesce(t,''),'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ.','aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC ')) $$;
create or replace function pg_temp.acha_func(cli uuid, nome_planilha text) returns uuid language sql stable as
$$
  with t as (select array_remove(regexp_split_to_array(trim(pg_temp.sem_acento(nome_planilha)),'\s+'),'') as p),
  f as (select id, regexp_split_to_array(trim(pg_temp.sem_acento(nome)),'\s+') as w
          from public.funcionarios where cliente_id = cli and situacao <> 'Desligado'),
  todas as (select f.id, f.w[1] = t.p[1] as mesmo_inicio from f, t
             where not exists (select 1 from unnest(t.p) x where not exists (select 1 from unnest(f.w) y where y like x || '%'))),
  -- sem nenhuma com todas as palavras: tenta só a primeira e a última
  ponta as (select f.id, true as mesmo_inicio from f, t
             where not exists (select 1 from todas) and f.w[1] = t.p[1]
               and exists (select 1 from unnest(f.w[2:]) y where y like t.p[array_length(t.p,1)] || '%')),
  cand as (select * from todas union all select * from ponta),
  melhor as (select * from cand where mesmo_inicio or not exists (select 1 from cand where mesmo_inicio))
  select case when (select count(*) from melhor) = 1 then (select id from melhor) end
$$;

update public.funcionarios f
   set folha_fixos = (coalesce(f.folha_fixos,'{}'::jsonb) - 'ajuda_sabado')
                     || jsonb_build_object('sem_sabado', true)
                     || case when coalesce(f.folha_fixos->>'ajuda_mes','') = '' then jsonb_build_object('ajuda_mes', 150) else '{}'::jsonb end
  from public.clientes c
 where c.nome = 'Oliveira Biguaçu' and f.id = pg_temp.acha_func(c.id, 'Luana');

delete from public.folha_lancamentos l
 using public.clientes c
 where c.nome = 'Oliveira Biguaçu' and l.cliente_id = c.id and l.coluna = 'ajuda_dia'
   and l.funcionario_id = pg_temp.acha_func(c.id, 'Luana')
   and public.folha_aberta(l.cliente_id, l.competencia);

notify pgrst, 'reload schema';

select coalesce(f.nome,'NÃO ENCONTRADA') as colaboradora, f.folha_fixos->>'ajuda_mes' as ajuda_fixa_mes,
       f.folha_fixos->>'sem_sabado' as sabado_nao_conta, f.folha_fixos->>'gratificacoes' as gratificacao_fixa
  from public.clientes c left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, 'Luana')
 where c.nome = 'Oliveira Biguaçu';
