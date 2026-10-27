-- =====================================================================
-- v47 · Gestão financeira, fase 3: conciliação bancária pelo OFX
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v45. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): importar o OFX de cada conta e conciliar com o que está lançado.
--   fin_ofx          = cada linha do extrato do banco (não repete ao importar o mesmo período de novo);
--   fin_movimentos.ofx_id liga o lançamento do sistema à linha do banco (= conciliado);
--   fin_conc_regras  = o que a Carol lançou para um texto do banco; as próximas linhas com o
--                      mesmo texto já chegam com o lançamento sugerido, só para aprovar (como no Bom Controle).
-- Por enquanto só o escritório vê e edita.

alter table public.fin_contas add column if not exists ofx_banco text;   -- BANKID do OFX (033, 077, 748...)
alter table public.fin_contas add column if not exists ofx_conta text;   -- ACCTID do OFX

create table if not exists public.fin_ofx (
  id           uuid primary key default gen_random_uuid(),
  cliente_id   uuid not null references public.clientes on delete cascade,
  conta_id     uuid not null references public.fin_contas on delete cascade,
  chave        text not null,          -- data|valor|histórico|ordem: o FITID do Santander muda a cada exportação
  fitid        text,
  data         date not null,
  valor        numeric(12,2) not null, -- positivo = entrou; negativo = saiu
  memo         text,
  nome         text,
  documento    text,                   -- CNPJ/CPF que aparece no histórico (Sicredi)
  padrao       text,                   -- histórico sem números, para reconhecer as regras
  ignorado     boolean not null default false,
  importado_em timestamptz not null default now(),
  importado_por uuid references auth.users default auth.uid(),
  unique (conta_id, chave)
);
create index if not exists fin_ofx_conta_data on public.fin_ofx (conta_id, data);

alter table public.fin_movimentos add column if not exists ofx_id uuid references public.fin_ofx on delete set null;
create unique index if not exists fin_mov_ofx on public.fin_movimentos (ofx_id) where ofx_id is not null;

create table if not exists public.fin_conc_regras (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes on delete cascade,
  padrao        text not null,         -- trecho do histórico do banco que identifica o lançamento
  tipo          text not null check (tipo in ('entrada','saida')),
  descricao     text,
  categoria     text,
  pessoa_nome   text,
  conta_destino uuid references public.fin_contas on delete set null,  -- transferência entre contas (ex.: aplicação)
  usos          integer not null default 0,
  atualizado_em timestamptz not null default now(),
  unique (cliente_id, padrao, tipo)
);

alter table public.fin_ofx         enable row level security;
alter table public.fin_conc_regras enable row level security;
drop policy if exists esc_tudo on public.fin_ofx;
create policy esc_tudo on public.fin_ofx         for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.fin_conc_regras;
create policy esc_tudo on public.fin_conc_regras for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on public.fin_ofx, public.fin_conc_regras to authenticated;

select 'Atualização v47 (conciliação bancária pelo OFX) concluída' as resultado;
