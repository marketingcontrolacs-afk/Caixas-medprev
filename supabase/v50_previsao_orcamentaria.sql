-- =====================================================================
-- v50 · Gestão financeira: previsão orçamentária
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v49. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): preencher o orçamento a cada 6 meses, por categoria,
-- e comparar com o realizado para ver se a empresa cumpriu.

create table if not exists public.fin_orcamento (
  id           uuid primary key default gen_random_uuid(),
  cliente_id   uuid not null references public.clientes on delete cascade,
  mes          date not null,              -- primeiro dia do mês
  categoria    text not null,
  valor        numeric(12,2) not null default 0,
  atualizado_em timestamptz not null default now(),
  unique (cliente_id, mes, categoria)
);

alter table public.fin_orcamento enable row level security;
drop policy if exists esc_tudo on public.fin_orcamento;
create policy esc_tudo on public.fin_orcamento for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on public.fin_orcamento to authenticated;

select 'Atualização v50 (previsão orçamentária) concluída' as resultado;
