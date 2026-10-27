-- =====================================================================
-- v52 · Gestão financeira: fatura do cartão de crédito e plano de contas por empresa
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v51. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026):
--   1) Cartão de crédito: uma conta do tipo "Cartão de crédito" só nas empresas que têm cartão.
--      Tudo o que foi pago com o cartão é lançado nela (fin_movimentos, com o mês da fatura).
--      No fim do mês a soma é conferida com a fatura do banco e a fatura é fechada: vira uma conta
--      a pagar (fin_titulos.fatura_id). O pagamento da fatura é uma transferência da conta bancária
--      para o cartão, então a despesa entra uma vez só (na compra, com a categoria dela).
--   2) Plano de contas por empresa: cada empresa usa o plano padrão (plano_contas, o mesmo para todas)
--      ou um plano próprio (fin_plano), escolhido em Gestão financeira › Cadastros › Plano de contas.

-- cartão: dia em que a fatura fecha, dia em que vence e a conta bancária que paga a fatura
alter table public.fin_contas add column if not exists cartao_fechamento smallint check (cartao_fechamento between 1 and 31);
alter table public.fin_contas add column if not exists cartao_vencimento smallint check (cartao_vencimento between 1 and 31);
alter table public.fin_contas add column if not exists cartao_conta_pag uuid references public.fin_contas on delete set null;

-- lançamentos no cartão: mês da fatura (dia 1), parcelas e a nota enviada pelo cliente (Financeiro › Cartão de crédito)
alter table public.fin_movimentos add column if not exists fatura date;
alter table public.fin_movimentos add column if not exists forma text;          -- forma de pagamento (Pix, Boleto...), para o relatório por forma
alter table public.fin_movimentos add column if not exists parcela smallint;
alter table public.fin_movimentos add column if not exists parcelas smallint;
alter table public.fin_movimentos add column if not exists grupo_id uuid;
alter table public.fin_movimentos add column if not exists cartao_nota_id uuid references public.cartao_notas on delete set null;
create unique index if not exists fin_mov_cartao_nota on public.fin_movimentos (cartao_nota_id, parcela) where cartao_nota_id is not null;
create index if not exists fin_mov_fatura on public.fin_movimentos (conta_id, fatura) where fatura is not null;

-- faturas fechadas (conferidas com a fatura do banco)
create table if not exists public.fin_faturas (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes on delete cascade,
  conta_id    uuid not null references public.fin_contas on delete cascade,   -- o cartão
  mes         date not null,                -- mês da fatura (dia 1)
  vencimento  date not null,
  valor       numeric(12,2) not null,       -- valor da fatura do banco
  fechada_em  timestamptz not null default now(),
  fechada_por uuid references auth.users default auth.uid(),
  unique (conta_id, mes)
);
alter table public.fin_titulos add column if not exists fatura_id uuid references public.fin_faturas on delete set null;
create unique index if not exists fin_titulos_fatura on public.fin_titulos (fatura_id) where fatura_id is not null;

-- plano de contas próprio da empresa
alter table public.clientes add column if not exists plano_proprio boolean not null default false;
create table if not exists public.fin_plano (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes on delete cascade,
  codigo      text,
  categoria   text not null,
  tipo        text not null default 'Despesa' check (tipo in ('Despesa','Receita')),
  ativo       boolean not null default true,
  unique (cliente_id, categoria)
);

alter table public.fin_faturas enable row level security;
alter table public.fin_plano   enable row level security;
drop policy if exists esc_tudo on public.fin_faturas;
create policy esc_tudo on public.fin_faturas for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.fin_plano;
create policy esc_tudo on public.fin_plano   for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on public.fin_faturas, public.fin_plano to authenticated;

select 'Atualização v52 (cartão de crédito e plano de contas por empresa) concluída' as resultado;
