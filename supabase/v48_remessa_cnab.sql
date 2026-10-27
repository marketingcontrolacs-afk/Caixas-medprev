-- =====================================================================
-- v48 · Gestão financeira: remessa de pagamentos CNAB 240 (Sicredi)
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v47. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): gerar o arquivo de remessa para o banco pagar os boletos e os Pix
-- das contas a pagar, e ler o arquivo de retorno para saber o que foi agendado, pago ou recusado.
--   fin_contas.cnab_*   = dados do convênio de pagamento da conta (código do convênio e nº da última remessa);
--   fin_remessas        = cada arquivo gerado (guarda o conteúdo para baixar de novo);
--   fin_remessa_itens   = cada pagamento do arquivo, ligado à conta a pagar, com a situação do retorno.
-- Por enquanto só o escritório vê e edita.

alter table public.fin_contas add column if not exists cnab_convenio text;          -- código do convênio de pagamentos no banco
alter table public.fin_contas add column if not exists cnab_seq integer not null default 0;  -- nº da última remessa gerada

create table if not exists public.fin_remessas (
  id             uuid primary key default gen_random_uuid(),
  cliente_id     uuid not null references public.clientes on delete cascade,
  conta_id       uuid not null references public.fin_contas on delete cascade,
  nsa            integer not null,          -- número sequencial do arquivo
  arquivo        text not null,             -- nome do arquivo .REM
  conteudo       text not null,
  qtd            integer not null default 0,
  valor          numeric(12,2) not null default 0,
  gerado_em      timestamptz not null default now(),
  gerado_por     uuid references auth.users default auth.uid(),
  retorno_em     timestamptz,
  unique (conta_id, nsa)
);

create table if not exists public.fin_remessa_itens (
  id             uuid primary key default gen_random_uuid(),
  remessa_id     uuid not null references public.fin_remessas on delete cascade,
  cliente_id     uuid not null references public.clientes on delete cascade,
  conta_id       uuid not null references public.fin_contas on delete cascade,
  titulo_id      uuid references public.fin_titulos on delete set null,
  seu_numero     text not null,             -- vai no arquivo e volta no retorno
  forma          text not null,             -- boleto, consumo, pix
  favorecido     text,
  valor          numeric(12,2) not null,
  data_pagamento date not null,
  status         text not null default 'enviado' check (status in ('enviado','agendado','pago','recusado','excluido')),
  ocorrencia     text,                      -- códigos do retorno (ex.: BD, 00, AG)
  atualizado_em  timestamptz not null default now(),
  unique (conta_id, seu_numero)
);
create index if not exists fin_rem_itens_titulo on public.fin_remessa_itens (titulo_id);
create index if not exists fin_rem_itens_cliente on public.fin_remessa_itens (cliente_id);

alter table public.fin_remessas      enable row level security;
alter table public.fin_remessa_itens enable row level security;
drop policy if exists esc_tudo on public.fin_remessas;
create policy esc_tudo on public.fin_remessas      for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.fin_remessa_itens;
create policy esc_tudo on public.fin_remessa_itens for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on public.fin_remessas, public.fin_remessa_itens to authenticated;

select 'Atualização v48 (remessa de pagamentos CNAB) concluída' as resultado;
