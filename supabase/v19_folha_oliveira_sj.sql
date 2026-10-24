-- =====================================================================
-- v19 · Folha da Oliveira SJ e descontos parcelados
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez, e não depende da ordem dos outros
-- arquivos (só precisa do v14, a folha de pagamento). Não cadastra ninguém: liga a planilha aos
-- colaboradores que já estão no sistema (importados das férias) pelo nome, e ignora quem saiu.
--  1. Modelo da planilha de cada empresa (título, grupos, férias e rescisão no fim) e valores fixos por colaborador.
--  2. Dias úteis do mês, para a ajuda de custo por dia.
--  3. Descontos parcelados: vale de atendimentos MP e adiantamentos, com o mês e o valor de cada parcela.
--  4. Oliveira SJ: colunas da planilha "Folha de Pgto - Oliveira SJ", fixos e as guias e adiantamentos da planilha.

alter table public.clientes     add column if not exists folha_modelo jsonb;
alter table public.funcionarios add column if not exists folha_fixos  jsonb not null default '{}'::jsonb;
alter table public.folha_meses  add column if not exists dias_uteis   int check (dias_uteis between 0 and 31);

create table if not exists public.folha_parcelamentos (
  id             uuid primary key default gen_random_uuid(),
  cliente_id     uuid not null references public.clientes on delete cascade,
  funcionario_id uuid not null references public.funcionarios on delete cascade,
  coluna         text not null default 'vale_mp',      -- coluna da folha em que a parcela é descontada
  emissao        date,
  guia           text,
  usuario        text,                                 -- quem usou o atendimento
  descricao      text,
  valor_total    numeric(12,2) not null,
  parcelas       jsonb not null default '[]'::jsonb,   -- [{"c":"2026-10","v":198.00}, ...]
  origem         text,                                 -- linha da planilha importada (para não duplicar)
  criado_por     uuid default auth.uid(),
  criado_em      timestamptz not null default now(),
  unique (cliente_id, origem)
);
create index if not exists folha_parcelamentos_cli on public.folha_parcelamentos(cliente_id);

alter table public.folha_parcelamentos enable row level security;
drop policy if exists esc_tudo on public.folha_parcelamentos;
create policy esc_tudo on public.folha_parcelamentos for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.folha_parcelamentos;
create policy op_ver on public.folha_parcelamentos for select using (pode_ver(cliente_id,'folha'));
drop policy if exists op_gravar on public.folha_parcelamentos;
create policy op_gravar on public.folha_parcelamentos for all
  using (pode_lancar(cliente_id,'folha')) with check (pode_lancar(cliente_id,'folha'));

-- ---------------------------------------------------------------------
-- Oliveira SJ
-- ---------------------------------------------------------------------
update public.clientes
   set folha_colunas = array['vale_mp','adiantamento','faltas_data','gratificacoes','premio_whats','assiduidade','ajuda_dia','he65','he100','observacoes'],
       folha_modelo  = '{"titulo": "Oliveira e Schmidt Matriz", "rotulo_nome": "Funcionário", "cargo": false, "mesclar": true, "grupos": {"D": "Descontos", "P": "Proventos"}, "ferias": true, "corte": 20, "arquivo": "Folha de Pgto - {empresa} {mes}.{ano}", "resc_itens": [["premiacao", "Premiação"], ["horas_extras", "Horas Extras 50%"], ["vale_alimentacao", "Vale alimentação"], ["vale_combustivel", "Vale combustível"], ["adiantamento", "Adiantamento"], ["vale_mp", "Vale (Atendimentos MP)"]]}'::jsonb,
       bpo_rh = true
 where nome = 'Oliveira SJ';

-- Acha o colaborador ativo pelo nome da planilha: cada palavra tem que ser o começo de uma palavra do
-- nome completo, sem acento e sem maiúscula ("Fernanda Ap wilvert" acha "Fernanda Aparecida Wilvert").
-- Se der mais de um, fica o que começa com a mesma palavra; se continuar empatado, não liga.
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

drop table if exists pg_temp.sj_fixos;
create temp table sj_fixos(nome text, fixos jsonb);
insert into sj_fixos values
  ('Fernanda','{"assiduidade": 100, "gratificacoes": "Função", "ajuda_dia": 13, "ajuda_sabado": 100, "observacoes": "*Ajuda de custo $13,00 dia (Ajuda de custo Transporte)/ Sábado R$100,00"}'::jsonb),
  ('Ana Beatriz','{"assiduidade": 100}'::jsonb),
  ('Ana Paula Agostinho','{"assiduidade": 100}'::jsonb),
  ('Danielle Areias Pereira','{"assiduidade": 100, "ajuda_dia": 13, "ajuda_sabado": 70, "observacoes": "*Ajuda de custo $13,00 por dia (verificar sabados trabalhados e incluir)/ Sábado R$70,00"}'::jsonb),
  ('Eduarda','{"assiduidade": 100}'::jsonb),
  ('Fellype','{"assiduidade": 100}'::jsonb),
  ('Isabelle','{"assiduidade": 100}'::jsonb),
  ('Janifer Rodrigues de Cristo','{"assiduidade": 100}'::jsonb),
  ('João Victor','{"assiduidade": 100}'::jsonb),
  ('Joice Carvalho','{"assiduidade": 100}'::jsonb),
  ('José Luiz Arruda','{"assiduidade": 100}'::jsonb),
  ('Marcia Terezinha L Goulart','{"assiduidade": 100, "observacoes": "Sábados - Gratificação de 70,00"}'::jsonb),
  ('Maria Cristina','{"assiduidade": 100}'::jsonb),
  ('Maria Eduarda Hoffmann','{"assiduidade": 100}'::jsonb),
  ('Maria Julia Hugen','{"assiduidade": 100}'::jsonb),
  ('Naiara Michelly','{"assiduidade": 100}'::jsonb),
  ('Paula Fernanda Souza','{"assiduidade": 100, "gratificacoes": "Função", "observacoes": "01/02/2026 mudança de cargo Gerente com cargo de confiança"}'::jsonb),
  ('Tatiany','{"assiduidade": 100}'::jsonb),
  ('Veronica','{"assiduidade": 100}'::jsonb),
  ('Gabrielle Freitas','{}'::jsonb);

drop table if exists pg_temp.sj_parc;
create temp table sj_parc(origem text, nome text, coluna text, emissao date, guia text, usuario text, valor numeric, descricao text, parcelas jsonb);
insert into sj_parc values
  ('sj-vale-4','Ana Paula Agostinho','vale_mp','2026-07-15'::date,'26855142','Pedro Vitor',61.0,null,'[{"c": "2026-07", "v": 61.0}]'::jsonb),
  ('sj-vale-5','Danielle Areias','vale_mp','2026-01-05'::date,'25012895',null,66.0,null,'[{"c": "2026-01", "v": 66.0}]'::jsonb),
  ('sj-vale-6','Danielle Areias','vale_mp','2026-01-06'::date,'25052656',null,66.0,null,'[{"c": "2026-01", "v": 66.0}]'::jsonb),
  ('sj-vale-7','Danielle Areias','vale_mp','2026-01-13'::date,'25109713',null,200.0,null,'[{"c": "2026-01", "v": 100.0}, {"c": "2026-02", "v": 100.0}]'::jsonb),
  ('sj-vale-8','Danielle Areias','vale_mp','2026-01-23'::date,'25217438','Danielle Areias Pereira',66.0,null,'[{"c": "2026-02", "v": 66.0}]'::jsonb),
  ('sj-vale-9','Danielle Areias','vale_mp','2026-02-10'::date,'25385107','Alice Areias Pereira',17.0,null,'[{"c": "2026-02", "v": 17.0}]'::jsonb),
  ('sj-vale-10','Danielle Areias','vale_mp','2026-02-12'::date,'25423614','Rafaela S. Areias',66.0,null,'[{"c": "2026-02", "v": 66.0}]'::jsonb),
  ('sj-vale-11','Danielle Areias','vale_mp','2026-02-20'::date,'25474489','Danielle Areias Pereira',40.0,null,'[{"c": "2026-02", "v": 40.0}]'::jsonb),
  ('sj-vale-12','Danielle Areias','vale_mp','2026-03-06'::date,'25607131','Rafaela S. Areias',66.0,null,'[{"c": "2026-03", "v": 66.0}]'::jsonb),
  ('sj-vale-13','Danielle Areias','vale_mp','2026-03-12'::date,'25668029','Rafaela S. Areias',66.0,null,'[{"c": "2026-03", "v": 66.0}]'::jsonb),
  ('sj-vale-14','Danielle Areias','vale_mp','2026-03-16'::date,'25704663','Rafaela S. Areias',160.0,null,'[{"c": "2026-03", "v": 80.0}, {"c": "2026-04", "v": 80.0}]'::jsonb),
  ('sj-vale-15','Danielle Areias','vale_mp','2026-03-20'::date,'25753775','Alice Areias Pereira',140.0,null,'[{"c": "2026-03", "v": 140.0}]'::jsonb),
  ('sj-vale-16','Danielle Areias','vale_mp','2026-04-07'::date,'25891502','Rafaela S. Areias',66.0,null,'[{"c": "2026-04", "v": 66.0}]'::jsonb),
  ('sj-vale-17','Danielle Areias','vale_mp','2026-04-23'::date,'26058544','Alice Areias Pereira',5.0,null,'[{"c": "2026-05", "v": 5.0}]'::jsonb),
  ('sj-vale-18','Danielle Areias','vale_mp','2026-04-30'::date,'26131442','Danielle Areias Pereira',230.0,null,'[{"c": "2026-05", "v": 57.5}, {"c": "2026-06", "v": 57.5}, {"c": "2026-07", "v": 57.5}, {"c": "2026-08", "v": 57.5}]'::jsonb),
  ('sj-vale-19','Danielle Areias','vale_mp','2026-04-30'::date,'26131480','Danielle Areias Pereira',330.0,null,'[{"c": "2026-05", "v": 82.5}, {"c": "2026-06", "v": 82.5}, {"c": "2026-07", "v": 82.5}, {"c": "2026-08", "v": 82.5}]'::jsonb),
  ('sj-vale-20','Danielle Areias','vale_mp','2026-05-19'::date,'26304684','Alice Areias Pereira',60.0,null,'[{"c": "2026-05", "v": 60.0}]'::jsonb),
  ('sj-vale-21','Danielle Areias','vale_mp','2026-06-05'::date,'26474605','Danielle Areias Pereira',1460.0,null,'[{"c": "2026-06", "v": 365.0}, {"c": "2026-07", "v": 365.0}, {"c": "2026-08", "v": 365.0}, {"c": "2026-09", "v": 365.0}]'::jsonb),
  ('sj-vale-22','Danielle Areias','vale_mp','2026-06-12'::date,'26525472','Rafaela S. Areias',60.0,null,'[{"c": "2026-06", "v": 60.0}]'::jsonb),
  ('sj-vale-23','Fernanda','vale_mp','2026-01-23'::date,'25226476','Mychelle Mendes',12.0,null,'[{"c": "2026-02", "v": 12.0}]'::jsonb),
  ('sj-vale-24','Fernanda Ap wilvert','vale_mp','2026-04-09'::date,'25909026','Henrique Wilvert souto',77.0,null,'[{"c": "2026-04", "v": 38.5}, {"c": "2026-05", "v": 38.5}]'::jsonb),
  ('sj-vale-25','Fernanda Ap wilvert','vale_mp','2026-04-24'::date,'26071112','maria eduarda wilvert',140.0,null,'[{"c": "2026-05", "v": 46.67}, {"c": "2026-06", "v": 46.67}, {"c": "2026-07", "v": 46.67}]'::jsonb),
  ('sj-vale-26','Fernanda Ap wilvert','vale_mp','2026-04-24'::date,'26074219','Henrique Wilvert souto',66.0,null,'[{"c": "2026-05", "v": 33.0}, {"c": "2026-06", "v": 33.0}]'::jsonb),
  ('sj-vale-27','Fernanda Ap wilvert','vale_mp','2026-05-05'::date,'26154982','maria eduarda wilvert',30.0,null,'[{"c": "2026-05", "v": 30.0}]'::jsonb),
  ('sj-vale-28','Fernanda Ap wilvert','vale_mp','2026-05-07'::date,'26190364','Henrique Wilvert souto',77.0,null,'[{"c": "2026-05", "v": 38.5}, {"c": "2026-06", "v": 38.5}]'::jsonb),
  ('sj-vale-29','Fernanda Ap wilvert','vale_mp','2026-07-10'::date,'26808540','Henrique Wilvert souto',83.0,null,'[{"c": "2026-07", "v": 41.5}, {"c": "2026-08", "v": 41.5}]'::jsonb),
  ('sj-vale-30','Gabrielle  Freitas','vale_mp','2026-02-04'::date,'25267437','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-02", "v": 66.0}]'::jsonb),
  ('sj-vale-31','Gabrielle  Freitas','vale_mp','2026-02-06'::date,'25357534','Deivison Luiz',110.0,null,'[{"c": "2026-02", "v": 55.0}, {"c": "2026-03", "v": 55.0}]'::jsonb),
  ('sj-vale-32','Gabrielle  Freitas','vale_mp','2026-03-04'::date,'25585525','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-03", "v": 66.0}]'::jsonb),
  ('sj-vale-33','Gabrielle  Freitas','vale_mp','2026-04-02'::date,'25872720','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-04", "v": 66.0}]'::jsonb),
  ('sj-vale-34','Gabrielle  Freitas','vale_mp','2026-04-10'::date,'25941781','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-04", "v": 22.0}, {"c": "2026-05", "v": 22.0}, {"c": "2026-06", "v": 22.0}]'::jsonb),
  ('sj-vale-35','Gabrielle  Freitas','vale_mp','2026-04-10'::date,'25941831','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-04", "v": 22.0}, {"c": "2026-05", "v": 22.0}, {"c": "2026-06", "v": 22.0}]'::jsonb),
  ('sj-vale-36','Gabrielle  Freitas','vale_mp','2026-04-10'::date,'25941831','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-04", "v": 22.0}, {"c": "2026-05", "v": 22.0}, {"c": "2026-06", "v": 22.0}]'::jsonb),
  ('sj-vale-37','Gabrielle  Freitas','vale_mp','2026-05-04'::date,'26142612','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-05", "v": 66.0}]'::jsonb),
  ('sj-vale-38','Gabrielle  Freitas','vale_mp','2026-05-15'::date,'26273262','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-05", "v": 22.0}, {"c": "2026-06", "v": 22.0}, {"c": "2026-07", "v": 22.0}]'::jsonb),
  ('sj-vale-39','Gabrielle  Freitas','vale_mp','2026-05-15'::date,'26273270','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-05", "v": 22.0}, {"c": "2026-06", "v": 22.0}, {"c": "2026-07", "v": 22.0}]'::jsonb),
  ('sj-vale-40','Gabrielle  Freitas','vale_mp','2026-05-15'::date,'26273287','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-05", "v": 22.0}, {"c": "2026-06", "v": 22.0}, {"c": "2026-07", "v": 22.0}]'::jsonb),
  ('sj-vale-41','Gabrielle  Freitas','vale_mp','2026-06-01'::date,'26401331','Adenir Terezinha',45.0,null,'[{"c": "2026-06", "v": 45.0}]'::jsonb),
  ('sj-vale-42','Gabrielle  Freitas','vale_mp','2026-06-26'::date,'26670602','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-07", "v": 66.0}]'::jsonb),
  ('sj-vale-43','Gabrielle  Freitas','vale_mp','2026-07-03'::date,'26735176','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-07", "v": 66.0}]'::jsonb),
  ('sj-vale-44','Gabrielle  Freitas','vale_mp','2026-07-17'::date,'26872754','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-07", "v": 66.0}]'::jsonb),
  ('sj-vale-45','Gabrielle  Freitas','vale_mp','2026-07-24'::date,'26941617','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-08", "v": 22.0}, {"c": "2026-09", "v": 22.0}, {"c": "2026-10", "v": 22.0}]'::jsonb),
  ('sj-vale-46','Gabrielle  Freitas','vale_mp','2026-07-29'::date,'26985030','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-08", "v": 51.33}, {"c": "2026-09", "v": 51.33}, {"c": "2026-10", "v": 51.34}]'::jsonb),
  ('sj-vale-47','Gabrielle  Freitas','vale_mp','2026-08-17'::date,'27167750','Gabrielle Freitas Santos',154.0,null,'[{"c": "2026-09", "v": 22.0}]'::jsonb),
  ('sj-vale-48','joão victor c. de moraes','vale_mp','2026-04-27'::date,'26084641','joao victor c. de moraes',132.0,null,'[{"c": "2026-05", "v": 132.0}]'::jsonb),
  ('sj-vale-49','marcia Goulart','vale_mp','2026-02-25'::date,'25461788','Davi Luiz Goulart',77.0,null,'[{"c": "2026-03", "v": 77.0}]'::jsonb),
  ('sj-vale-50','marcia Goulart','vale_mp','2026-03-27'::date,'25804374','Davi Luiz Goulart',77.0,null,'[{"c": "2026-04", "v": 77.0}]'::jsonb),
  ('sj-vale-51','marcia Goulart','vale_mp','2026-05-25'::date,'26363041','Davi Luiz Goulart',77.0,null,'[{"c": "2026-06", "v": 77.0}]'::jsonb),
  ('sj-vale-52','marcia Goulart','vale_mp','2026-07-07'::date,'26703013','Davi Luiz Goulart',83.0,null,'[{"c": "2026-07", "v": 83.0}]'::jsonb),
  ('sj-vale-53','marcia Goulart','vale_mp','2026-08-11'::date,'26781421','Jose Cantidio Goulart',215.0,null,'[{"c": "2026-08", "v": 71.67}, {"c": "2026-09", "v": 71.67}, {"c": "2026-10", "v": 71.66}]'::jsonb),
  ('sj-vale-54','Maria Eduarda Hoffman','vale_mp','2026-01-16'::date,'25092357',null,150.0,null,'[{"c": "2026-01", "v": 75.0}, {"c": "2026-02", "v": 75.0}]'::jsonb),
  ('sj-vale-55','Maria Eduarda Hoffmann','vale_mp','2026-02-20'::date,'25473853','Maria Eduarda Hoffmann',95.0,null,'[{"c": "2026-02", "v": 95.0}]'::jsonb),
  ('sj-vale-56','Maria Eduarda Hoffmann','vale_mp','2026-03-24'::date,'25777682','Maria Eduarda Hoffmann',150.0,null,'[{"c": "2026-04", "v": 150.0}]'::jsonb),
  ('sj-vale-57','Maria Eduarda Hoffmann','vale_mp','2026-08-17'::date,'27079190','Maria Eduarda Hoffmann',160.0,null,'[{"c": "2026-08", "v": 160.0}]'::jsonb),
  ('sj-vale-58','Maria Julia','vale_mp','2025-11-06'::date,'24575333',null,110.0,null,'[{"c": "2026-01", "v": 36.67}, {"c": "2026-02", "v": 36.66}]'::jsonb),
  ('sj-vale-59','Maria Julia','vale_mp','2025-11-06'::date,'24527348',null,250.0,null,'[{"c": "2026-01", "v": 83.33}, {"c": "2026-02", "v": 83.34}]'::jsonb),
  ('sj-vale-60','Maria Julia','vale_mp','2026-07-17'::date,'26877060','Maria julia H. de Oliveira',799.0,null,'[{"c": "2026-07", "v": 199.75}, {"c": "2026-08", "v": 199.75}, {"c": "2026-09", "v": 199.75}, {"c": "2026-10", "v": 199.75}]'::jsonb),
  ('sj-vale-61','Paula Fernanda','vale_mp','2026-02-04'::date,'25314002','Roberta de souza',85.0,null,'[{"c": "2026-02", "v": 85.0}]'::jsonb),
  ('sj-vale-62','Paula Fernanda Souza','vale_mp','2026-01-06'::date,'24822726',null,50.0,null,'[{"c": "2026-01", "v": 50.0}]'::jsonb),
  ('sj-vale-63','Tatiany','vale_mp','2025-12-17'::date,'24937070',null,148.0,null,'[{"c": "2026-01", "v": 49.33}, {"c": "2026-02", "v": 49.34}]'::jsonb),
  ('sj-vale-64','José Luiz','vale_mp','2026-09-04'::date,'27357953','José Luiz',990.0,null,'[{"c": "2026-09", "v": 198.0}, {"c": "2026-10", "v": 198.0}, {"c": "2026-11", "v": 198.0}, {"c": "2026-12", "v": 198.0}, {"c": "2027-01", "v": 198.0}]'::jsonb),
  ('sj-vale-65','Gabrielle  Freitas','vale_mp','2026-08-21'::date,'27221289','Gabrielle Freitas Santos',66.0,null,'[{"c": "2026-09", "v": 66.0}]'::jsonb),
  ('sj-adto-10','Ana Paula Agostinho','adiantamento',null::date,null,null,2500.0,'Parcelado em 10x','[{"c": "2025-12", "v": 250.0}, {"c": "2026-01", "v": 250.0}, {"c": "2026-02", "v": 250.0}, {"c": "2026-03", "v": 250.0}, {"c": "2026-04", "v": 250.0}, {"c": "2026-05", "v": 250.0}, {"c": "2026-06", "v": 250.0}, {"c": "2026-07", "v": 250.0}, {"c": "2026-08", "v": 250.0}, {"c": "2026-09", "v": 250.0}]'::jsonb),
  ('sj-adto-11','Ana Paula Agostinho','adiantamento','2026-01-12'::date,null,null,780.0,'Parcelado em 9x','[{"c": "2026-01", "v": 86.67}, {"c": "2026-02", "v": 86.67}, {"c": "2026-03", "v": 86.67}, {"c": "2026-04", "v": 86.67}, {"c": "2026-05", "v": 86.67}, {"c": "2026-06", "v": 86.67}, {"c": "2026-07", "v": 86.67}, {"c": "2026-08", "v": 86.67}, {"c": "2026-09", "v": 86.67}]'::jsonb),
  ('sj-adto-15','Ana Paula Agostinho','adiantamento','2026-03-05'::date,null,null,693.0,'Férias erradas, em 3x','[{"c": "2026-03", "v": 231.0}, {"c": "2026-04", "v": 231.0}, {"c": "2026-05", "v": 231.0}]'::jsonb)
;

-- valores fixos (somam ao que já houver no cadastro)
update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || x.fixos
  from sj_fixos x, public.clientes c
 where c.nome = 'Oliveira SJ' and f.id = pg_temp.acha_func(c.id, x.nome);

-- guias do vale e adiantamentos parcelados (cada linha da planilha entra uma vez só)
insert into public.folha_parcelamentos(cliente_id, funcionario_id, coluna, emissao, guia, usuario, descricao, valor_total, parcelas, origem)
select c.id, pg_temp.acha_func(c.id, p.nome), p.coluna, p.emissao, p.guia, p.usuario, p.descricao, p.valor, p.parcelas, p.origem
  from sj_parc p, public.clientes c
 where c.nome = 'Oliveira SJ' and pg_temp.acha_func(c.id, p.nome) is not null
on conflict (cliente_id, origem) do nothing;

grant select, insert, update, delete on all tables in schema public to authenticated;
notify pgrst, 'reload schema';

-- Conferência: quem da planilha foi ligado a quem do sistema
select x.nome as nome_na_planilha, coalesce(f.nome, 'NÃO ENCONTRADO (saiu ou está com outro nome)') as colaborador_no_sistema,
       (select count(*) from public.folha_parcelamentos p where p.funcionario_id = f.id) as descontos_parcelados
  from (select nome from sj_fixos union select nome from sj_parc) x
  left join public.clientes c on c.nome = 'Oliveira SJ'
  left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, x.nome)
 order by 2, 1;
