-- =====================================================================
-- v60 · Portal da contabilidade
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v44 e da v59.
-- Pedido da Carol (28/10/2026):
-- 1. Acesso "Contabilidade" para o contador: vê só as empresas liberadas, confere o de-para e exporta.
-- 2. Plano de contas da contabilidade importado por empresa (planilha ou CSV do sistema contábil).
-- 3. De-para: cada categoria e cada conta (banco, tesouraria, cartão) ligada a uma conta contábil.
--    O portal sugere pelo nome; o contador confere e confirma.
-- 4. Layout de exportação do sistema contábil: o escritório importa um arquivo de exemplo e configura
--    as colunas antes do contador validar.
-- 5. Fechamento do mês: o escritório fecha o mês e o contador exporta os lançamentos realizados.

alter table public.acessos drop constraint if exists acessos_modulo_check;
alter table public.acessos add constraint acessos_modulo_check
  check (modulo in ('caixa','pagar','cartao','tesouraria','ferias','folha','repasse','tarefas','premio','beneficios','colab','ponto','contabil'));

-- plano de contas da contabilidade (por empresa)
create table if not exists public.ctb_plano (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes on delete cascade,
  codigo        text not null,          -- código reduzido usado na importação
  classificacao text,                   -- ex.: 3.1.01.001
  nome          text not null,
  analitica     boolean not null default true,
  criado_em     timestamptz not null default now(),
  unique (cliente_id, codigo)
);
-- de-para: categoria (nome) ou conta financeira (id) -> conta contábil
create table if not exists public.ctb_depara (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes on delete cascade,
  origem_tipo   text not null check (origem_tipo in ('categoria','conta')),
  origem        text not null,          -- nome da categoria ou id da conta financeira
  conta_codigo  text,
  sugerido      boolean not null default false,
  confirmado    boolean not null default false,
  confirmado_por uuid references auth.users,
  confirmado_em timestamptz,
  unique (cliente_id, origem_tipo, origem)
);
-- layout do arquivo de importação do sistema contábil (por empresa)
create table if not exists public.ctb_layout (
  cliente_id    uuid primary key references public.clientes on delete cascade,
  sistema       text,                   -- nome do sistema contábil
  colunas       jsonb not null default '[]',  -- [{titulo, campo, fixo}]
  separador     text not null default ';',
  formato_data  text not null default 'dd/mm/aaaa',
  decimal       text not null default ',',
  cabecalho     boolean not null default true,
  extensao      text not null default 'csv',
  atualizado_por uuid references auth.users default auth.uid(),
  atualizado_em timestamptz not null default now()
);
-- meses fechados pelo escritório e exportados pelo contador
create table if not exists public.ctb_fechamentos (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes on delete cascade,
  mes           date not null,          -- primeiro dia do mês
  fechado_por   uuid references auth.users default auth.uid(),
  fechado_em    timestamptz not null default now(),
  exportado_por uuid references auth.users,
  exportado_em  timestamptz,
  unique (cliente_id, mes)
);

alter table public.ctb_plano       enable row level security;
alter table public.ctb_depara      enable row level security;
alter table public.ctb_layout      enable row level security;
alter table public.ctb_fechamentos enable row level security;

-- escritório: tudo; contador: plano e de-para da empresa liberada; layout e fechamento só para ver
do $$ declare t text; begin
  foreach t in array array['ctb_plano','ctb_depara','ctb_layout','ctb_fechamentos'] loop
    execute format('drop policy if exists esc_tudo on public.%I', t);
    execute format('create policy esc_tudo on public.%I for all using (eh_escritorio()) with check (eh_escritorio())', t);
    execute format('drop policy if exists ctb_ver on public.%I', t);
    execute format('create policy ctb_ver on public.%I for select using (pode_ver(cliente_id, ''contabil''))', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
  foreach t in array array['ctb_plano','ctb_depara'] loop
    execute format('drop policy if exists ctb_editar on public.%I', t);
    execute format('create policy ctb_editar on public.%I for all using (pode_ver(cliente_id, ''contabil'')) with check (pode_ver(cliente_id, ''contabil''))', t);
  end loop;
end $$;

-- o contador lê o que precisa para conferir e exportar (só das empresas liberadas)
do $$ declare t text; begin
  foreach t in array array['fin_plano','fin_contas','fin_movimentos'] loop
    execute format('drop policy if exists ctb_ver on public.%I', t);
    execute format('create policy ctb_ver on public.%I for select using (pode_ver(cliente_id, ''contabil''))', t);
  end loop;
end $$;

-- o contador marca o mês como exportado
create or replace function public.ctb_exportado(p_cli uuid, p_mes date) returns void
language plpgsql security definer set search_path = public as
$$ begin
  if not pode_ver(p_cli, 'contabil') then raise exception 'Sem acesso a esta empresa'; end if;
  update ctb_fechamentos set exportado_por = auth.uid(), exportado_em = now() where cliente_id = p_cli and mes = p_mes;
  if not found then raise exception 'O escritório ainda não fechou este mês'; end if;
end $$;
grant execute on function public.ctb_exportado(uuid, date) to authenticated;

-- situação da configuração por empresa (aviso no menu enquanto faltar alguma coisa)
create or replace function public.ctb_status() returns table(cliente_id uuid, plano int, layout boolean, confirmados int, contador boolean)
language sql stable security definer set search_path = public as
$$ select c.id,
          (select count(*) from ctb_plano p where p.cliente_id = c.id)::int,
          exists (select 1 from ctb_layout l where l.cliente_id = c.id and jsonb_array_length(l.colunas) > 0),
          (select count(*) from ctb_depara d where d.cliente_id = c.id and d.confirmado and d.conta_codigo is not null)::int,
          exists (select 1 from acessos a where a.cliente_id = c.id and a.modulo = 'contabil')
     from clientes c
    where c.ativo is not false and c.bpo_financeiro is not false and pode_ver(c.id, 'contabil') $$;
grant execute on function public.ctb_status() to authenticated;

notify pgrst, 'reload schema';

select 'Portal da contabilidade instalado' as ok;
