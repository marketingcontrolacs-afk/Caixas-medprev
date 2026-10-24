-- =====================================================================
-- v23 · Folha de Palhoça e Biguaçu pelas planilhas de cada filial
-- =====================================================================
-- Rode no SQL Editor do Supabase depois da v19, v20 e v21. Pode rodar mais de uma vez.
--  1. Título e nomes das colunas como nas planilhas ("Oliveira e Schmidt - Filial ...", "Adiantamento Salarial").
--  2. Valores fixos: os verdes (premiação de R$ 250 da Ana Paula e da Joice em Palhoça e da Zilma em Biguaçu),
--     a gratificação "Função" do Claudinei e as observações de sábado da Bianca e da Luana.
--  3. Guias do vale (Atendimentos MP) da Joice em Palhoça, com as parcelas de cada mês.
--  4. Premiação de outubro da Cryslaine (Palhoça), que na lista estava como "Gislaine".

update public.clientes
   set folha_modelo = folha_modelo || jsonb_build_object('titulo','Oliveira e Schmidt - Filial Palhoça',
         'titulos', jsonb_build_object('adiantamento','Adiantamento Salarial'),
         'abas', jsonb_build_object('vale_mp','Vale (Guias MP)','adiantamento','Adiantamento'))
 where nome = 'Oliveira Palhoça' and folha_modelo is not null;
update public.clientes
   set folha_modelo = folha_modelo || jsonb_build_object('titulo','Oliveira e Schmidt - Filial Biguaçu',
         'titulos', jsonb_build_object('adiantamento','Adiantamento Salarial'))
 where nome = 'Oliveira Biguaçu' and folha_modelo is not null;

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


drop table if exists pg_temp.fil_fixos;
create temp table fil_fixos(empresa text, nome text, fixos jsonb);
insert into fil_fixos values
  ('Oliveira Palhoça','Claudinei','{"gratificacoes":"Função"}'::jsonb),
  ('Oliveira Palhoça','Ana Paula Dias Santos','{"premio_whats":250}'::jsonb),
  ('Oliveira Palhoça','Joice','{"premio_whats":250}'::jsonb),
  ('Oliveira Palhoça','Bianca','{"observacoes":"Sábado - Gratificação 70,00"}'::jsonb),
  ('Oliveira Biguaçu','Zilma','{"premio_whats":250}'::jsonb),
  ('Oliveira Biguaçu','Luana','{"observacoes":"Gratificação de R$150,00 quebra de cx dos sábados"}'::jsonb);

update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || x.fixos
  from fil_fixos x join public.clientes c on c.nome = x.empresa
 where f.id = pg_temp.acha_func(c.id, x.nome);

drop table if exists pg_temp.pal_parc;
create temp table pal_parc(origem text, nome text, emissao date, guia text, usuario text, valor numeric, parcelas jsonb);
insert into pal_parc values
  ('pal-vale-4','Joice Cabral de Souza','2026-02-23'::date,'25473304','Mauricio',121.0,'[{"c": "2026-03", "v": 30.25}, {"c": "2026-04", "v": 30.25}, {"c": "2026-05", "v": 30.25}, {"c": "2026-06", "v": 30.25}]'::jsonb),
  ('pal-vale-5','Joice Cabral de Souza','2026-02-24'::date,'23759604','Mauricio',227.0,'[{"c": "2026-03", "v": 56.75}, {"c": "2026-04", "v": 56.75}, {"c": "2026-05", "v": 56.75}, {"c": "2026-06", "v": 56.75}]'::jsonb),
  ('pal-vale-6','Joice Cabral de Souza','2026-02-24'::date,'25490145','Mauricio',435.0,'[{"c": "2026-03", "v": 108.75}, {"c": "2026-04", "v": 108.75}, {"c": "2026-05", "v": 108.75}, {"c": "2026-06", "v": 108.75}]'::jsonb),
  ('pal-vale-7','Joice Cabral de Souza','2026-02-24'::date,'25489423','Mauricio',200.0,'[{"c": "2026-03", "v": 50.0}, {"c": "2026-04", "v": 50.0}, {"c": "2026-05", "v": 50.0}, {"c": "2026-06", "v": 50.0}]'::jsonb),
  ('pal-vale-8','Joice Cabral de Souza','2026-02-24'::date,'25489477','Mauricio',40.0,'[{"c": "2026-03", "v": 10.0}, {"c": "2026-04", "v": 10.0}, {"c": "2026-05", "v": 10.0}, {"c": "2026-06", "v": 10.0}]'::jsonb),
  ('pal-vale-9','Joice Cabral de Souza','2026-02-24'::date,'25500801','Marina Cabral de Souza',75.0,'[{"c": "2026-03", "v": 18.75}, {"c": "2026-04", "v": 18.75}, {"c": "2026-05", "v": 18.75}, {"c": "2026-06", "v": 18.75}]'::jsonb),
  ('pal-vale-10','Joice Cabral de Souza','2026-03-13'::date,'25688064','Joice Cabral de Souza',121.0,'[{"c": "2026-03", "v": 60.5}, {"c": "2026-04", "v": 60.5}]'::jsonb),
  ('pal-vale-11','Joice Cabral de Souza','2026-03-19'::date,'25576815','Joice Cabral de Souza',140.0,'[{"c": "2026-03", "v": 70.0}, {"c": "2026-04", "v": 70.0}]'::jsonb),
  ('pal-vale-12','Joice Cabral de Souza','2026-03-19'::date,'25738776','Marina Cabral de Souza',70.0,'[{"c": "2026-03", "v": 35.0}, {"c": "2026-04", "v": 35.0}]'::jsonb),
  ('pal-vale-13','Joice Cabral de Souza','2026-03-31'::date,'25754433','Joice Cabral de Souza',115.0,'[{"c": "2026-04", "v": 38.33}, {"c": "2026-05", "v": 38.33}, {"c": "2026-06", "v": 38.34}]'::jsonb),
  ('pal-vale-14','Joice Cabral de Souza','2026-04-10'::date,'23738687','Marina Cabral de Souza',66.0,'[{"c": "2026-04", "v": 33.0}, {"c": "2026-05", "v": 33.0}]'::jsonb),
  ('pal-vale-15','Joice Cabral de Souza','2026-04-15'::date,'25996435','Joice Cabral de Souza',55.0,'[{"c": "2026-04", "v": 27.5}, {"c": "2026-05", "v": 27.5}]'::jsonb),
  ('pal-vale-16','Joice Cabral de Souza','2026-05-20'::date,'26217999','Marina Cabral de Souza',67.5,'[{"c": "2026-05", "v": 67.5}]'::jsonb),
  ('pal-vale-17','Joice Cabral de Souza','2026-05-20'::date,'26237581','Marina Cabral de Souza',67.5,'[{"c": "2026-05", "v": 67.5}]'::jsonb),
  ('pal-vale-18','Joice Cabral de Souza','2026-07-09'::date,'26792372','Marina Cabral de Souza',66.0,'[{"c": "2026-07", "v": 33.0}, {"c": "2026-08", "v": 33.0}]'::jsonb),
  ('pal-vale-19','Joice Cabral de Souza','2026-08-07'::date,'27035229','Marina Cabral de Souza',66.0,'[{"c": "2026-08", "v": 33.0}, {"c": "2026-09", "v": 33.0}]'::jsonb),
  ('pal-vale-20','Joice Cabral de Souza','2026-09-11'::date,'27416775','Marina Cabral de Souza',66.0,'[{"c": "2026-09", "v": 33.0}, {"c": "2026-10", "v": 33.0}]'::jsonb),
  ('pal-vale-21','Joice Cabral de Souza','2026-09-24'::date,'29518568','Marina Cabral de Souza',66.0,'[{"c": "2026-09", "v": 33.0}, {"c": "2026-10", "v": 33.0}]'::jsonb);

insert into public.folha_parcelamentos(cliente_id, funcionario_id, coluna, emissao, guia, usuario, valor_total, parcelas, origem)
select c.id, pg_temp.acha_func(c.id, p.nome), 'vale_mp', p.emissao, p.guia, p.usuario, p.valor, p.parcelas, p.origem
  from pal_parc p, public.clientes c
 where c.nome = 'Oliveira Palhoça' and pg_temp.acha_func(c.id, p.nome) is not null
on conflict (cliente_id, origem) do nothing;

-- premiação de outubro da Cryslaine (o nome pode estar com y ou com i no cadastro)
insert into public.folha_lancamentos(cliente_id, competencia, funcionario_id, coluna, quantidade)
select c.id, date '2026-10-01', x.id, 'premio_whats', 515
  from public.clientes c,
       lateral (select coalesce(pg_temp.acha_func(c.id,'Cryslaine'), pg_temp.acha_func(c.id,'Crislaine'), pg_temp.acha_func(c.id,'Gislaine')) as id) x
 where c.nome = 'Oliveira Palhoça' and x.id is not null
   and not exists (select 1 from public.folha_lancamentos l where l.funcionario_id = x.id and l.competencia = date '2026-10-01' and l.coluna = 'premio_whats');

notify pgrst, 'reload schema';

-- Conferência
select x.empresa, x.nome as nome_na_planilha, coalesce(f.nome,'NÃO ENCONTRADO') as colaborador_no_sistema, f.folha_fixos,
       (select count(*) from public.folha_parcelamentos p where p.funcionario_id = f.id) as descontos_parcelados
  from (select empresa, nome from fil_fixos union select 'Oliveira Palhoça', 'Cryslaine') x
  join public.clientes c on c.nome = x.empresa
  left join public.funcionarios f on f.id = coalesce(pg_temp.acha_func(c.id, x.nome), case when x.nome='Cryslaine' then pg_temp.acha_func(c.id,'Crislaine') end)
 order by 1, 2;
