-- =====================================================================
-- v40 · Taxa da 2ª via do cartão (benefícios) e sábado de R$ 70 (Bianca, Márcia e Danielle)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): quando o colaborador perde o cartão do vale alimentação ou do
-- combustível, a 2ª via custa R$ 9,00, que é descontada do benefício. A linha do pedido guarda a taxa.

alter table public.beneficios_pedidos add column if not exists taxa numeric(12,2);

-- Sábado trabalhado (Carol, 27/10): Bianca (Palhoça), Márcia e Danielle (SJ) recebem R$ 70,00 por sábado, não R$ 50.
-- O R$ 50 é o padrão de quem não tinha valor no cadastro (contrato antigo), que a importação do ponto grava sozinha.
-- A folha calcula com o valor do cadastro, então a ajuda de custo de outubro já se acerta.

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

with x(empresa, nome, valor) as (values ('Oliveira SJ','Márcia Terezinha',70),('Oliveira SJ','Danielle Areias Pereira',70),('Oliveira Palhoça','Bianca',70))
update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || jsonb_build_object('ajuda_sabado', x.valor)
  from x join public.clientes c on c.nome = x.empresa
 where f.id = pg_temp.acha_func(c.id, x.nome);

notify pgrst, 'reload schema';

with x(empresa, nome) as (values ('Oliveira SJ','Márcia Terezinha'),('Oliveira SJ','Danielle Areias Pereira'),('Oliveira Palhoça','Bianca'))
select x.empresa, x.nome as procurado, coalesce(f.nome,'NÃO ENCONTRADO') as colaborador, f.folha_fixos->>'ajuda_sabado' as sabado_rs
  from x join public.clientes c on c.nome = x.empresa
  left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, x.nome) order by 1, 2;
