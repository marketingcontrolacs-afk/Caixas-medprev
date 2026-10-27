-- =====================================================================
-- v44 · Gestão financeira, fase 1: cadastros
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): módulo "Gestão financeira" para, no futuro, substituir o ERP
-- (contas a pagar e a receber, conciliação bancária por OFX e conciliação dos recebíveis de cartão).
-- Esta fase cria a base: as contas bancárias de cada empresa e o cadastro de clientes e fornecedores.
-- Por enquanto só o escritório vê e edita.
-- Os fornecedores começam com a lista do Bom Controle (fornecedores_bc, do v11), valendo para todas as empresas.

create table if not exists public.fin_contas (
  id           uuid primary key default gen_random_uuid(),
  cliente_id   uuid not null references public.clientes on delete cascade,
  nome         text not null,               -- como aparece nas telas, ex.: "Sicredi 12345-6"
  tipo         text not null default 'Conta corrente',
  banco        text,
  agencia      text,
  conta        text,
  conta_bc     text,                        -- nome da conta no Bom Controle
  saldo_inicial numeric(12,2) not null default 0,
  saldo_data   date,
  ativo        boolean not null default true,
  obs          text,
  criado_em    timestamptz not null default now()
);
create index if not exists fin_contas_cliente on public.fin_contas (cliente_id);

-- clientes e fornecedores; cliente_id vazio = vale para todas as empresas
create table if not exists public.fin_pessoas (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid references public.clientes on delete cascade,
  papel         text not null default 'fornecedor' check (papel in ('cliente','fornecedor','ambos')),
  nome          text not null,              -- razão social ou nome completo
  fantasia      text,
  documento     text,                       -- CNPJ/CPF
  grupo         text,                       -- ex.: Convênio, Empresa, Particular
  email         text,
  telefone      text,
  cidade        text,
  pix_tipo      text,
  pix_chave     text,
  banco         text,
  agencia       text,
  conta         text,
  fornecedor_bc text,                       -- chave em fornecedores_bc
  ativo         boolean not null default true,
  obs           text,
  criado_em     timestamptz not null default now()
);
create index if not exists fin_pessoas_cliente on public.fin_pessoas (cliente_id);
create unique index if not exists fin_pessoas_bc on public.fin_pessoas (fornecedor_bc) where fornecedor_bc is not null;

alter table public.fin_contas  enable row level security;
alter table public.fin_pessoas enable row level security;
drop policy if exists esc_tudo on public.fin_contas;
create policy esc_tudo on public.fin_contas  for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.fin_pessoas;
create policy esc_tudo on public.fin_pessoas for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on public.fin_contas, public.fin_pessoas to authenticated;

-- carga inicial: fornecedores do Bom Controle (os que já estão aqui não são repetidos)
insert into public.fin_pessoas (papel, nome, fantasia, documento, fornecedor_bc, ativo)
select 'fornecedor', f.razao_social, nullif(f.fantasia, ''), nullif(f.documento, ''), f.chave, not f.bloqueado
from public.fornecedores_bc f
where not exists (select 1 from public.fin_pessoas p where p.fornecedor_bc = f.chave);

select 'Atualização v44 (Gestão financeira: cadastros) concluída. Fornecedores: '
       || (select count(*) from public.fin_pessoas where papel <> 'cliente') as resultado;
