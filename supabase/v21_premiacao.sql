-- =====================================================================
-- v21 · Premiação que o cliente preenche + premiação de outubro/2026 das Oliveira
-- =====================================================================
-- Rode no SQL Editor do Supabase depois da v19 e da v20. Pode rodar mais de uma vez.
--  1. Liga a tela RH › Premiação para as 3 Oliveira (coluna Premiação Whatsapp da folha).
--  2. Lança a premiação de outubro/2026 da lista que a Oliveira mandou (bônus call center),
--     ligando o nome da lista ao colaborador ativo do sistema. Quem já tem premiação lançada
--     em outubro não é mexido. A Eliete (Biguaçu) é sem registro e não entra na folha.

update public.clientes
   set folha_modelo = coalesce(folha_modelo,'{}'::jsonb) || '{"premiacao":["premio_whats"]}'::jsonb
 where nome in ('Oliveira SJ','Oliveira Biguaçu','Oliveira Palhoça');

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


drop table if exists pg_temp.premio_out;
create temp table premio_out(empresa text, nome text, valor numeric);
insert into premio_out values
  ('Oliveira SJ','João Victor',415),
  ('Oliveira SJ','Isabelle',475),
  ('Oliveira SJ','Fellype',240),
  ('Oliveira SJ','Maria Julia',355),
  ('Oliveira SJ','Maria Eduarda Hoffmann',310),
  ('Oliveira SJ','Veronica',310),
  ('Oliveira SJ','Eduarda',155),
  ('Oliveira SJ','Naiara',310),
  ('Oliveira SJ','Ana Beatriz',290),
  ('Oliveira SJ','Maria Cristina',450),
  ('Oliveira Palhoça','Bianca',1070),
  ('Oliveira Palhoça','Gabriela T',450),
  ('Oliveira Palhoça','Cryslaine',515),
  ('Oliveira Biguaçu','Luana',220),
  ('Oliveira Biguaçu','Silmara',350);

insert into public.folha_lancamentos(cliente_id, competencia, funcionario_id, coluna, quantidade)
select c.id, date '2026-10-01', pg_temp.acha_func(c.id, p.nome), 'premio_whats', p.valor
  from premio_out p join public.clientes c on c.nome = p.empresa
 where pg_temp.acha_func(c.id, p.nome) is not null
   and not exists (select 1 from public.folha_lancamentos l where l.cliente_id = c.id and l.competencia = date '2026-10-01'
                     and l.coluna = 'premio_whats' and l.funcionario_id = pg_temp.acha_func(c.id, p.nome));

notify pgrst, 'reload schema';

-- Conferência: nome da lista, colaborador do sistema e valor lançado em outubro
select p.empresa, p.nome as nome_na_lista, coalesce(f.nome,'NÃO ENCONTRADO (lance pela tela Premiação)') as colaborador_no_sistema,
       (select sum(l.quantidade) from public.folha_lancamentos l where l.funcionario_id = f.id and l.competencia = date '2026-10-01' and l.coluna = 'premio_whats') as premiacao_outubro
  from premio_out p join public.clientes c on c.nome = p.empresa
  left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, p.nome)
 order by 1, 2;
