-- =====================================================================
-- v28 · Oliveira SJ: Fellyphe não pode fazer hora extra
-- =====================================================================
-- Rode no SQL Editor do Supabase depois da v19. Pode rodar mais de uma vez.
-- O cadastro pode estar como Fellype ou Fellyphe: procura pelo começo "Fel" (Felipe, Fellype, Fellyphe).
-- O Fellyphe (SJ) é menor de idade e trabalha 6h: não pode fazer hora extra. Ao importar o espelho de ponto, a HE dele
-- não é lançada; vira um alerta nas observações da folha. Para mudar, marque ou desmarque "Não pode fazer hora extra"
-- em Folha › Colaboradores e valores fixos.
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
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || '{"sem_he":true}'::jsonb
  from public.clientes c
 where c.nome = 'Oliveira SJ' and f.id = pg_temp.acha_func(c.id, 'Fel');

notify pgrst, 'reload schema';

select c.nome as empresa, coalesce(f.nome,'NÃO ENCONTRADO') as colaborador, f.folha_fixos->>'sem_he' as nao_pode_he
  from public.clientes c left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, 'Fel')
 where c.nome = 'Oliveira SJ';
