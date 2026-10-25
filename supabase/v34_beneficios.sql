-- =====================================================================
-- v34 · RH › Pedido de benefícios (vale transporte, combustível e alimentação)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Substitui as planilhas "VC e VA / VR e VT" da Oliveira (Carol, 25/10/2026):
--  * o pedido é feito no fim do mês para o mês seguinte (competência = mês de uso), descontando as faltas
--    e atestados do mês do pedido e as férias que caem no mês de uso;
--  * VT/combustível: quantidade = (dias do mês − (feriados e domingos + sábados de folga + faltas)) × 2;
--  * alimentação por dia trabalhado: dias = dias do mês − (sábados, domingos e feriados + faltas); ou valor fixo;
--  * combustível só na Oliveira e na BJ; a Oliveira não desconta VT/VA na folha; as demais descontam
--    6% de VT e R$ 1,00 de VA (empresa sem regra confirmada usa essa, com alerta para conferir).
-- O cadastro de cada colaborador fica em funcionarios.folha_fixos (vt_tipo, vt_empresa, vt_unit, vt_sab_nao,
-- va_tipo, va_empresa, va_valor) e a regra da empresa em clientes.folha_modelo.beneficios.

create table if not exists public.beneficios_pedidos (
  id             uuid primary key default gen_random_uuid(),
  cliente_id     uuid not null references public.clientes on delete cascade,
  competencia    date not null,                 -- mês de uso (1º dia)
  funcionario_id uuid not null references public.funcionarios on delete cascade,
  tipo           text not null check (tipo in ('vt','comb','va')),
  empresa        text,
  va_tipo        text check (va_tipo in ('dia','fixo')),
  dias_mes       int,
  fer_dom        int,                           -- VT: feriados e domingos; VA: sábados, domingos e feriados
  sab_nao        int,
  faltas         numeric,
  quant          numeric,                       -- VT: passagens; VA: dias a receber
  unitario       numeric,
  total          numeric,
  obs            text,
  criado_em      timestamptz not null default now(),
  unique (cliente_id, competencia, funcionario_id, tipo)
);
create table if not exists public.beneficios_meses (
  cliente_id  uuid not null references public.clientes on delete cascade,
  competencia date not null,
  status      text not null default 'Rascunho' check (status in ('Rascunho','Pedido feito')),
  pedido_em   timestamptz,
  pedido_por  uuid references auth.users default auth.uid(),
  primary key (cliente_id, competencia)
);
create table if not exists public.beneficios_pendencias (
  id             uuid primary key default gen_random_uuid(),
  cliente_id     uuid not null references public.clientes on delete cascade,
  funcionario_id uuid references public.funcionarios on delete set null,
  texto          text not null,
  competencia    date,                          -- pedido em que deve ser descontado
  resolvida      boolean not null default false,
  criado_em      timestamptz not null default now()
);

do $$ declare t text; begin
  foreach t in array array['beneficios_pedidos','beneficios_meses','beneficios_pendencias'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists esc_tudo on public.%I', t);
    execute format('create policy esc_tudo on public.%I for all using (eh_escritorio()) with check (eh_escritorio())', t);
    execute format('drop policy if exists op_ver on public.%I', t);
    execute format('create policy op_ver on public.%I for select using (pode_ver(cliente_id,''folha''))', t);
    execute format('drop policy if exists op_gravar on public.%I', t);
    execute format('create policy op_gravar on public.%I for all using (pode_lancar(cliente_id,''folha'')) with check (pode_lancar(cliente_id,''folha''))', t);
  end loop;
end $$;
grant select, insert, update, delete on public.beneficios_pedidos, public.beneficios_meses, public.beneficios_pendencias to authenticated;

-- regra das três Oliveiras: tem combustível e não desconta VT/VA na folha
update public.clientes
   set folha_modelo = coalesce(folha_modelo,'{}'::jsonb) || '{"beneficios":{"desconta":false,"combustivel":true,"confirmado":true}}'::jsonb
 where nome in ('Oliveira SJ','Oliveira Biguaçu','Oliveira Palhoça');

-- cadastro dos benefícios, pelas planilhas de outubro/2026 (setembro na Palhoça)
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

create temp table ben_carga(empresa text, nome text, fx jsonb) on commit drop;
insert into ben_carga values
  -- São José: VT (Jotur, Estrela, Santa Terezinha), combustível e VR Alimentação R$ 32,50 por dia
  ('Oliveira SJ','Ana Beatriz','{"vt_tipo":"vt","vt_empresa":"Jotur","vt_unit":10.1,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Ana Paula Agostinho','{"vt_tipo":"vt","vt_empresa":"Sta Terezinha","vt_unit":10.23,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Fel','{"vt_tipo":"vt","vt_empresa":"Jotur","vt_unit":10.1,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":20.5}'),
  ('Oliveira SJ','João Victor','{"vt_tipo":"vt","vt_empresa":"Jotur","vt_unit":7,"vt_sab_nao":2,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Joice Carvalho','{"vt_tipo":"vt","vt_empresa":"Estrela","vt_unit":7.24,"vt_sab_nao":2,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Maria Julia','{"vt_tipo":"vt","vt_empresa":"Estrela","vt_unit":7.24,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Naiara','{"vt_tipo":"vt","vt_empresa":"Jotur","vt_unit":10.1,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Paula Fernanda','{"vt_tipo":"vt","vt_empresa":"Estrela","vt_unit":7.24,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Maria Eduarda Hoffmann','{"vt_tipo":"comb","vt_empresa":"VR Combustível","vt_unit":7,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Danielle','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Fernanda','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Gabrielle','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Isabelle','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Janifer','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','José Luiz','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Márcia','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Tatiany','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Maria Cristina','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Veronica','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira SJ','Eduarda','{"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  -- Biguaçu: Setuf (site novo), combustível e VR Alimentação
  ('Oliveira Biguaçu','Luana','{"vt_tipo":"vt","vt_empresa":"Biguaçu (site novo)","vt_unit":10.1,"vt_sab_nao":1,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira Biguaçu','Zilma','{"vt_tipo":"vt","vt_empresa":"Biguaçu (site novo)","vt_unit":10.23,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  ('Oliveira Biguaçu','Silmara','{"vt_tipo":"comb","vt_empresa":"VR Combustível","vt_unit":10.1,"vt_sab_nao":1,"va_tipo":"dia","va_empresa":"VR Alimentação","va_valor":32.5}'),
  -- Palhoça: combustível e VR por dia trabalhado
  ('Oliveira Palhoça','Ana Paula','{"vt_tipo":"comb","vt_empresa":"VR Combustível","vt_unit":7,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR","va_valor":32.5}'),
  ('Oliveira Palhoça','Bianca','{"vt_tipo":"comb","vt_empresa":"VR Combustível","vt_unit":8.1,"vt_sab_nao":2,"va_tipo":"dia","va_empresa":"VR","va_valor":32.5}'),
  ('Oliveira Palhoça','Claudinei','{"vt_tipo":"comb","vt_empresa":"VR Combustível","vt_unit":7,"vt_sab_nao":2,"va_tipo":"dia","va_empresa":"VR","va_valor":32.5}'),
  ('Oliveira Palhoça','Crislaine','{"vt_tipo":"comb","vt_empresa":"VR Combustível","vt_unit":6.5,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR","va_valor":32.5}'),
  ('Oliveira Palhoça','Gabriela','{"vt_tipo":"comb","vt_empresa":"VR Combustível","vt_unit":11.5,"vt_sab_nao":1,"va_tipo":"dia","va_empresa":"VR","va_valor":32.5}'),
  ('Oliveira Palhoça','Joice','{"vt_tipo":"comb","vt_empresa":"VR Combustível","vt_unit":8.5,"vt_sab_nao":4,"va_tipo":"dia","va_empresa":"VR","va_valor":32.5}'),
  ('Oliveira Palhoça','Paloma','{"vt_tipo":"comb","vt_empresa":"VR Combustível","va_tipo":"dia","va_empresa":"VR","va_valor":32.5}');

-- só preenche quem ainda não tem benefício cadastrado (não apaga o que o escritório mudou na tela)
update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || b.fx
  from ben_carga b join public.clientes c on c.nome = b.empresa
 where f.id = pg_temp.acha_func(c.id, b.nome)
   and not (coalesce(f.folha_fixos,'{}'::jsonb) ?| array['vt_tipo','va_tipo']);

notify pgrst, 'reload schema';

select b.empresa, b.nome as procurado, coalesce(f.nome,'NÃO ENCONTRADO') as colaborador,
       f.folha_fixos->>'vt_tipo' as vt, f.folha_fixos->>'vt_empresa' as vt_empresa, f.folha_fixos->>'va_valor' as va_dia
  from ben_carga b join public.clientes c on c.nome = b.empresa
  left join public.funcionarios f on f.id = pg_temp.acha_func(c.id, b.nome)
 order by 1, 2;
