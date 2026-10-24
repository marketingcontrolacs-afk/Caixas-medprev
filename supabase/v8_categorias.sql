-- Portal do Cliente (Controlacs) - atualização v8: categoria automática nas contas a pagar (24/10/2026)
-- Rodar depois do v2_modulos.sql. Pode rodar mais de uma vez.
-- O escritório importa o plano de contas do Bom Controle (Configurações > Categorias).
-- A categoria de cada conta a pagar (e de cada nota do cartão) é sugerida sozinha:
--   1) pelo fornecedor: o sistema aprende a categoria escolhida da última vez para aquele fornecedor;
--   2) por regras de palavra (ex.: "celesc" -> Energia elétrica).
-- Sem categoria, a linha fica marcada na exportação do Bom Controle. Só o escritório vê e mexe nisso.

create table if not exists public.plano_contas (
  categoria text primary key,
  tipo      text not null default 'Despesa' check (tipo in ('Despesa','Receita')),
  ativo     boolean not null default true
);

create table if not exists public.categoria_regras (
  id        uuid primary key default gen_random_uuid(),
  palavra   text not null,
  categoria text not null
);

-- fornecedor_chave = nome do fornecedor em minúsculas, sem acento e sem espaços repetidos
create table if not exists public.fornecedor_categoria (
  fornecedor_chave text primary key,
  fornecedor       text not null,
  categoria        text not null,
  atualizado_em    timestamptz not null default now()
);

alter table public.contas_pagar add column if not exists categoria text;
alter table public.cartao_notas add column if not exists categoria text;

alter table public.plano_contas         enable row level security;
alter table public.categoria_regras     enable row level security;
alter table public.fornecedor_categoria enable row level security;
drop policy if exists esc_tudo on public.plano_contas;
create policy esc_tudo on public.plano_contas for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.categoria_regras;
create policy esc_tudo on public.categoria_regras for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.fornecedor_categoria;
create policy esc_tudo on public.fornecedor_categoria for all using (eh_escritorio()) with check (eh_escritorio());

grant select, insert, update, delete on all tables in schema public to authenticated;

select 'Atualização v8 (categorias automáticas) concluída' as resultado;
