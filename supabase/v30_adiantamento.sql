-- =====================================================================
-- v30 · Oliveira: adiantamento salarial de R$ 830 (Ana Paula, Joyce e Silmara)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Regra (Carol, 25/10): o adiantamento salarial é de no máximo R$ 830. Recebem: SJ Ana Paula Agostinho, Palhoça Joyce,
-- Biguaçu Silmara. Todo mês o valor já entra na folha em vermelho, com ✓ (confirmar), ✎ (mudar o valor) e ✗ (excluir).
-- Para mudar de vez, edite "Adiantamento salarial R$" em Folha › Colaboradores e valores fixos.
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

with q(empresa, nome) as (values ('Oliveira SJ','Ana Paula Agostinho'),('Oliveira Palhoça','Joyce'),('Oliveira Biguaçu','Silmara'))
update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || '{"adto_salarial":830}'::jsonb
  from q join public.clientes c on c.nome = q.empresa
 where f.id = pg_temp.acha_func(c.id, q.nome);

notify pgrst, 'reload schema';

with q(empresa, nome) as (values ('Oliveira SJ','Ana Paula Agostinho'),('Oliveira Palhoça','Joyce'),('Oliveira Biguaçu','Silmara'))
select q.empresa, q.nome as procurado, coalesce(f.nome,'NÃO ENCONTRADO') as colaborador, f.folha_fixos->>'adto_salarial' as adiantamento
  from q join public.clientes c on c.nome = q.empresa left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, q.nome);
