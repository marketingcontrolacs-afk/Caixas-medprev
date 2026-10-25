-- =====================================================================
-- v27 · Oliveira: valor do sábado trabalhado (ajuda de custo)
-- =====================================================================
-- Rode no SQL Editor do Supabase depois da v19. Pode rodar mais de uma vez.
-- Quem ganha por sábado trabalhado tem o valor em "Sábado R$" (Folha › Colaboradores e valores fixos). Ao importar o
-- espelho de ponto, os sábados trabalhados entram na Ajuda de custo (sábados × valor). Márcia (SJ) e Bianca (Palhoça)
-- recebem R$ 70; Danielle (R$ 70) e Fernanda (R$ 100) já estavam. Os de contrato antigo (R$ 50) se marcam na tela.
-- Biguaçu não tem: a Luana já recebe valor fixo.
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

drop table if exists pg_temp.sabado;
create temp table sabado(empresa text, nome text, valor numeric);
insert into sabado values
  ('Oliveira SJ','Márcia Terezinha',70),('Oliveira SJ','Danielle Areias Pereira',70),('Oliveira SJ','Fernanda',100),
  ('Oliveira Palhoça','Bianca',70);

update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || jsonb_build_object('ajuda_sabado', x.valor)
  from sabado x join public.clientes c on c.nome = x.empresa
 where f.id = pg_temp.acha_func(c.id, x.nome);

notify pgrst, 'reload schema';

select x.empresa, x.nome as nome_na_planilha, coalesce(f.nome,'NÃO ENCONTRADO') as colaborador, f.folha_fixos->>'ajuda_sabado' as sabado_rs
  from sabado x join public.clientes c on c.nome = x.empresa
  left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, x.nome) order by 1, 2;
