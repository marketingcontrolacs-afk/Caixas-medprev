-- Portal do Cliente (Controlacs) - atualização v7: Repasses de parceiros (24/10/2026)
-- Rodar depois do v3_rh_ferias.sql. Pode rodar mais de uma vez.
-- Dados bancários dos parceiros de cada empresa (Pix ou agência e conta) para os repasses
-- que a Controlacs paga toda quinta-feira.
-- O cliente (acesso "repasse / lançamento") cadastra parceiro novo, informa alteração de conta
-- e lança descontos (valor e motivo). Tudo fica em alerta até o escritório conferir:
--   parceiro novo        -> escritório confere os dados
--   alteração de conta   -> escritório aplica (a conta antiga fica guardada no histórico) ou recusa
--   desconto             -> escritório marca como descontado no pagamento da quinta

-- Módulo novo na tabela de acessos
alter table public.acessos drop constraint if exists acessos_modulo_check;
alter table public.acessos add constraint acessos_modulo_check
  check (modulo in ('caixa','pagar','cartao','tesouraria','ferias','folha','repasse'));

create table if not exists public.parceiros (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes on delete cascade,
  nome          text not null,
  especialidade text,
  titular       text,          -- favorecido da conta, se for outro nome (ex.: empresa do parceiro)
  cpf_cnpj      text,          -- do titular da conta
  banco         text,
  agencia       text,
  conta         text,
  tipo_conta    text,          -- Corrente / Poupança / Pagamento
  pix_tipo      text,          -- CPF / CNPJ / E-mail / Telefone / Aleatória
  pix_chave     text,
  obs           text,
  ativo         boolean not null default true,
  conferido     boolean not null default false,   -- dados conferidos pelo escritório
  criado_por    uuid references auth.users default auth.uid(),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz
);
create index if not exists parceiros_cliente on public.parceiros(cliente_id);

-- Pedido de alteração de conta: guarda os dados novos e, depois de aplicado, os antigos
create table if not exists public.parceiro_alteracoes (
  id              uuid primary key default gen_random_uuid(),
  parceiro_id     uuid not null references public.parceiros on delete cascade,
  cliente_id      uuid references public.clientes on delete cascade,   -- preenchido sozinho
  titular         text,
  cpf_cnpj        text,
  banco           text,
  agencia         text,
  conta           text,
  tipo_conta      text,
  pix_tipo        text,
  pix_chave       text,
  motivo          text,
  status          text not null default 'Pendente' check (status in ('Pendente','Aplicada','Recusada')),
  anterior        jsonb,
  nota_escritorio text,
  solicitado_por  uuid references auth.users default auth.uid(),
  solicitado_em   timestamptz not null default now(),
  resolvido_por   uuid references auth.users,
  resolvido_em    timestamptz
);
create index if not exists parceiro_alteracoes_cliente on public.parceiro_alteracoes(cliente_id, status);

-- Desconto a fazer no próximo repasse do parceiro
create table if not exists public.repasse_descontos (
  id              uuid primary key default gen_random_uuid(),
  parceiro_id     uuid not null references public.parceiros on delete cascade,
  cliente_id      uuid references public.clientes on delete cascade,   -- preenchido sozinho
  valor           numeric(12,2) not null check (valor > 0),
  motivo          text not null,
  referencia      text,          -- procedimento, paciente, data do atendimento
  status          text not null default 'Pendente' check (status in ('Pendente','Descontado','Cancelado')),
  descontado_em   date,
  nota_escritorio text,
  criado_por      uuid references auth.users default auth.uid(),
  criado_em       timestamptz not null default now(),
  resolvido_por   uuid references auth.users
);
create index if not exists repasse_descontos_cliente on public.repasse_descontos(cliente_id, status);

-- A empresa da alteração e do desconto é sempre a do parceiro
create or replace function public.empresa_do_parceiro() returns trigger
language plpgsql security definer set search_path = public as
$$ begin new.cliente_id := (select cliente_id from parceiros where id = new.parceiro_id); return new; end $$;
drop trigger if exists empresa_parceiro on public.parceiro_alteracoes;
create trigger empresa_parceiro before insert or update of parceiro_id on public.parceiro_alteracoes
  for each row execute function public.empresa_do_parceiro();
drop trigger if exists empresa_parceiro on public.repasse_descontos;
create trigger empresa_parceiro before insert or update of parceiro_id on public.repasse_descontos
  for each row execute function public.empresa_do_parceiro();

-- Escritório aplica a alteração de conta: guarda a conta antiga e grava a nova no parceiro
create or replace function public.aplicar_alteracao_conta(alt uuid, nota text default null) returns void
language plpgsql security definer set search_path = public as
$$ declare a parceiro_alteracoes; p parceiros;
begin
  if not eh_escritorio() then raise exception 'Só o escritório aplica alterações de conta'; end if;
  select * into a from parceiro_alteracoes where id = alt and status = 'Pendente' for update;
  if not found then raise exception 'Alteração não encontrada ou já resolvida'; end if;
  select * into p from parceiros where id = a.parceiro_id for update;
  update parceiro_alteracoes set status = 'Aplicada', resolvido_por = auth.uid(), resolvido_em = now(),
    nota_escritorio = coalesce(nota, nota_escritorio),
    anterior = jsonb_build_object('titular',p.titular,'cpf_cnpj',p.cpf_cnpj,'banco',p.banco,'agencia',p.agencia,
      'conta',p.conta,'tipo_conta',p.tipo_conta,'pix_tipo',p.pix_tipo,'pix_chave',p.pix_chave)
  where id = alt;
  update parceiros set titular = a.titular, cpf_cnpj = a.cpf_cnpj, banco = a.banco, agencia = a.agencia,
    conta = a.conta, tipo_conta = a.tipo_conta, pix_tipo = a.pix_tipo, pix_chave = a.pix_chave,
    conferido = true, atualizado_em = now()
  where id = a.parceiro_id;
end $$;

alter table public.parceiros           enable row level security;
alter table public.parceiro_alteracoes enable row level security;
alter table public.repasse_descontos   enable row level security;

drop policy if exists esc_tudo on public.parceiros;
create policy esc_tudo on public.parceiros for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.parceiros;
create policy op_ver on public.parceiros for select using (pode_ver(cliente_id,'repasse'));
drop policy if exists op_criar on public.parceiros;
create policy op_criar on public.parceiros for insert with check (pode_lancar(cliente_id,'repasse') and not conferido);
-- enquanto o escritório não confere, o cliente ainda corrige o cadastro; depois, só por alteração de conta
drop policy if exists op_editar on public.parceiros;
create policy op_editar on public.parceiros for update
  using (pode_lancar(cliente_id,'repasse') and not conferido) with check (pode_lancar(cliente_id,'repasse') and not conferido);

drop policy if exists esc_tudo on public.parceiro_alteracoes;
create policy esc_tudo on public.parceiro_alteracoes for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.parceiro_alteracoes;
create policy op_ver on public.parceiro_alteracoes for select using (pode_ver(cliente_id,'repasse'));
drop policy if exists op_criar on public.parceiro_alteracoes;
create policy op_criar on public.parceiro_alteracoes for insert with check (pode_lancar(cliente_id,'repasse') and status = 'Pendente');
drop policy if exists op_apagar on public.parceiro_alteracoes;
create policy op_apagar on public.parceiro_alteracoes for delete using (pode_lancar(cliente_id,'repasse') and status = 'Pendente');

drop policy if exists esc_tudo on public.repasse_descontos;
create policy esc_tudo on public.repasse_descontos for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.repasse_descontos;
create policy op_ver on public.repasse_descontos for select using (pode_ver(cliente_id,'repasse'));
drop policy if exists op_criar on public.repasse_descontos;
create policy op_criar on public.repasse_descontos for insert with check (pode_lancar(cliente_id,'repasse') and status = 'Pendente');
drop policy if exists op_editar on public.repasse_descontos;
create policy op_editar on public.repasse_descontos for update
  using (pode_lancar(cliente_id,'repasse') and status = 'Pendente') with check (pode_lancar(cliente_id,'repasse') and status = 'Pendente');
drop policy if exists op_apagar on public.repasse_descontos;
create policy op_apagar on public.repasse_descontos for delete using (pode_lancar(cliente_id,'repasse') and status = 'Pendente');

grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

select 'Atualização v7 (Repasses de parceiros) concluída' as resultado;
