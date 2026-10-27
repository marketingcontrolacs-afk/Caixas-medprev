-- =====================================================================
-- v41 · Tesouraria › Conferência física do saldo
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v2.
-- Pedido da Carol (27/10/2026): o responsável pela tesouraria conta o dinheiro e informa o valor físico.
-- O portal compara com o saldo do sistema na data, grava a diferença e a análise dos possíveis erros,
-- e mostra um alerta vermelho quando a empresa passa mais de 7 dias sem conferência.

create table if not exists public.tesouraria_conferencias (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes,
  data          date not null,
  valor_fisico  numeric(12,2) not null check (valor_fisico >= 0),
  saldo_sistema numeric(12,2) not null,
  diferenca     numeric(12,2) generated always as (valor_fisico - saldo_sistema) stored,
  analise       text,
  obs           text,
  conferido_por uuid references auth.users default auth.uid(),
  conferido_em  timestamptz not null default now()
);
create index if not exists tesouraria_conferencias_cli on public.tesouraria_conferencias (cliente_id, data desc);

alter table public.tesouraria_conferencias enable row level security;

drop policy if exists esc_tudo on public.tesouraria_conferencias;
create policy esc_tudo on public.tesouraria_conferencias for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.tesouraria_conferencias;
create policy op_ver on public.tesouraria_conferencias for select using (pode_ver(cliente_id,'tesouraria'));
drop policy if exists op_criar on public.tesouraria_conferencias;
create policy op_criar on public.tesouraria_conferencias for insert
  with check (pode_lancar(cliente_id,'tesouraria') and conferido_por = auth.uid());
-- quem conferiu pode apagar a própria conferência no mesmo dia (valor digitado errado)
drop policy if exists op_apagar on public.tesouraria_conferencias;
create policy op_apagar on public.tesouraria_conferencias for delete
  using (pode_lancar(cliente_id,'tesouraria') and conferido_por = auth.uid() and conferido_em > now() - interval '1 day');

grant select, insert, update, delete on public.tesouraria_conferencias to authenticated;

notify pgrst, 'reload schema';

select 'Conferência física da tesouraria instalada' as ok;
