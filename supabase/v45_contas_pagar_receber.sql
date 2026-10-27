-- =====================================================================
-- v45 · Gestão financeira, fase 2: contas a pagar e a receber e extrato da conta
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v44. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026):
--   fin_titulos    = cada conta a pagar ou a receber (uma linha por parcela), com o vencimento e o valor;
--   fin_movimentos = o que já aconteceu na conta bancária (entrada ou saída). A baixa de um título
--                    gera o movimento, e o extrato da conta é a lista desses movimentos, dia a dia.
-- Os boletos e notas que o cliente envia (contas_pagar) podem ser trazidos para fin_titulos (origem_id).
-- Por enquanto só o escritório vê e edita.

create table if not exists public.fin_titulos (
  id              uuid primary key default gen_random_uuid(),
  cliente_id      uuid not null references public.clientes on delete cascade,
  tipo            text not null check (tipo in ('pagar','receber')),
  pessoa_id       uuid references public.fin_pessoas on delete set null,
  pessoa_nome     text,                       -- nome como foi digitado (fica mesmo sem cadastro)
  descricao       text,
  documento       text,                       -- nº da NF, boleto ou outro documento
  categoria       text,
  competencia     date,                       -- mês a que a despesa ou receita pertence (dia 1)
  vencimento      date not null,
  valor           numeric(12,2) not null check (valor > 0),
  parcela         smallint not null default 1,
  parcelas        smallint not null default 1,
  grupo_id        uuid,                       -- mesmo valor para as parcelas de um lançamento
  conta_id        uuid references public.fin_contas on delete set null,   -- conta prevista
  forma           text,                       -- Boleto, Pix, Transferência, Cartão, Dinheiro, Débito automático
  linha_digitavel text,
  pix_chave       text,
  origem          text not null default 'manual',   -- manual | boleto_cliente
  origem_id       uuid,                       -- contas_pagar.id quando veio dos boletos enviados
  obs             text,
  criado_por      uuid references auth.users default auth.uid(),
  criado_em       timestamptz not null default now()
);
create index if not exists fin_titulos_cli_venc on public.fin_titulos (cliente_id, tipo, vencimento);
create unique index if not exists fin_titulos_origem on public.fin_titulos (origem_id) where origem_id is not null;

create table if not exists public.fin_movimentos (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes on delete cascade,
  conta_id    uuid not null references public.fin_contas on delete cascade,
  data        date not null,
  tipo        text not null check (tipo in ('entrada','saida')),
  valor       numeric(12,2) not null check (valor > 0),   -- o que entrou ou saiu da conta
  juros       numeric(12,2) not null default 0,           -- juros e multa pagos ou recebidos
  desconto    numeric(12,2) not null default 0,
  titulo_id   uuid references public.fin_titulos on delete cascade,  -- vazio = lançamento avulso
  transf_id   uuid,                           -- as duas pernas de uma transferência entre contas
  descricao   text,
  pessoa_nome text,
  documento   text,
  categoria   text,
  conciliado  boolean not null default false, -- fase 3 (OFX)
  criado_por  uuid references auth.users default auth.uid(),
  criado_em   timestamptz not null default now()
);
create index if not exists fin_mov_conta_data on public.fin_movimentos (conta_id, data);
create index if not exists fin_mov_titulo on public.fin_movimentos (titulo_id);

alter table public.fin_titulos    enable row level security;
alter table public.fin_movimentos enable row level security;
drop policy if exists esc_tudo on public.fin_titulos;
create policy esc_tudo on public.fin_titulos    for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.fin_movimentos;
create policy esc_tudo on public.fin_movimentos for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on public.fin_titulos, public.fin_movimentos to authenticated;

select 'Atualização v45 (contas a pagar e a receber e extrato da conta) concluída' as resultado;
