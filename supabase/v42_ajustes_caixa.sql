-- =====================================================================
-- v42 · Conferência de caixa: correções do escritório com histórico
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): na conferência do caixa o escritório corrige os valores lançados
-- pelo operador. O portal guarda como o operador lançou (antes da 1ª correção) e cada ajuste
-- (o que era, o que ficou, quem e quando), e mostra isso no dia conferido.

-- como o operador lançou o dia, guardado antes da primeira correção do escritório
create table if not exists public.caixa_original (
  fechamento_id uuid primary key references public.fechamentos on delete cascade,
  dados         jsonb not null,
  guardado_por  uuid references auth.users default auth.uid(),
  guardado_em   timestamptz not null default now()
);

-- um registro por valor alterado
create table if not exists public.caixa_ajustes (
  id            uuid primary key default gen_random_uuid(),
  fechamento_id uuid not null references public.fechamentos on delete cascade,
  campo         text not null,
  antes         text,
  depois        text,
  motivo        text,
  ajustado_por  uuid references auth.users default auth.uid(),
  ajustado_nome text,
  ajustado_em   timestamptz not null default now()
);
create index if not exists caixa_ajustes_fech on public.caixa_ajustes (fechamento_id, ajustado_em);

alter table public.caixa_original enable row level security;
alter table public.caixa_ajustes  enable row level security;

-- só o escritório vê e grava (igual à nota da conferência)
drop policy if exists esc_tudo on public.caixa_original;
create policy esc_tudo on public.caixa_original for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.caixa_ajustes;
create policy esc_tudo on public.caixa_ajustes for all using (eh_escritorio()) with check (eh_escritorio());

grant select, insert, update, delete on public.caixa_original to authenticated;
grant select, insert, update, delete on public.caixa_ajustes  to authenticated;

notify pgrst, 'reload schema';
