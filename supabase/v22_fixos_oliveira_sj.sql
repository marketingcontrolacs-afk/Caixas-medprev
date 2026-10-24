-- =====================================================================
-- v22 · Oliveira SJ: premiações e gratificação fixas (valores em verde na planilha)
-- =====================================================================
-- Rode no SQL Editor do Supabase depois da v19. Pode rodar mais de uma vez.
-- Os valores em verde na planilha de setembro são fixos: passam a entrar sozinhos todo mês.
-- Premiação Whatsapp fixa: Ana Paula, Janifer, Joice e Tatiany R$ 250, José Luiz R$ 350, Márcia R$ 400.
-- Gratificação fixa: Danielle R$ 600. Para mudar só num mês, altere a célula na folha.

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


drop table if exists pg_temp.sj_fixos2;
create temp table sj_fixos2(nome text, fixos jsonb);
insert into sj_fixos2 values
  ('Ana Paula Agostinho','{"premio_whats":250}'::jsonb),
  ('Janifer Rodrigues de Cristo','{"premio_whats":250}'::jsonb),
  ('Joice Carvalho','{"premio_whats":250}'::jsonb),
  ('José Luiz Arruda','{"premio_whats":350}'::jsonb),
  ('Marcia Terezinha L Goulart','{"premio_whats":400}'::jsonb),
  ('Tatiany','{"premio_whats":250}'::jsonb),
  ('Danielle Areias Pereira','{"gratificacoes":600}'::jsonb);

update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || x.fixos
  from sj_fixos2 x, public.clientes c
 where c.nome = 'Oliveira SJ' and f.id = pg_temp.acha_func(c.id, x.nome);

notify pgrst, 'reload schema';

select x.nome as nome_na_planilha, coalesce(f.nome,'NÃO ENCONTRADO') as colaborador_no_sistema, f.folha_fixos
  from sj_fixos2 x left join public.clientes c on c.nome = 'Oliveira SJ'
  left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, x.nome) order by 1;
