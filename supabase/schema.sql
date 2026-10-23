-- Caixas MedPrev (Controlacs) - instalação do banco de dados v1 (23/10/2026)
-- Depois de rodar este arquivo, rode também o v2_modulos.sql (acessos e módulos novos).
-- Operador: lança e corrige o caixa do próprio cliente até ser conferido.
-- Escritório: vê tudo, confere, cadastra clientes/usuários e exporta para o Bom Controle.

create table if not exists public.clientes (
  id             uuid primary key default gen_random_uuid(),
  nome           text not null unique,
  cnpj           text,
  abre_domingo   boolean not null default false,
  pasta_onedrive text,
  ativo          boolean not null default true
);

create table if not exists public.perfis (
  user_id    uuid primary key references auth.users on delete cascade,
  email      text,
  nome       text,
  papel      text not null default 'pendente' check (papel in ('pendente','operador','escritorio')),
  cliente_id uuid references public.clientes
);

create table if not exists public.fechamentos (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes,
  data        date not null,
  din_sis     numeric(12,2) not null default 0,
  din_cont    numeric(12,2) not null default 0,
  deb_sis     numeric(12,2) not null default 0,
  deb_maq     numeric(12,2) not null default 0,
  cred_sis    numeric(12,2) not null default 0,
  cred_maq    numeric(12,2) not null default 0,
  obs         text,
  enviado_por uuid references auth.users default auth.uid(),
  enviado_em  timestamptz not null default now(),
  conferido   boolean not null default false,
  unique (cliente_id, data)
);

create table if not exists public.saidas (
  id            uuid primary key default gen_random_uuid(),
  fechamento_id uuid not null references public.fechamentos on delete cascade,
  tipo          text not null,
  guia          text,
  parceiro      text,
  descricao     text,
  valor         numeric(12,2) not null check (valor > 0)
);

create table if not exists public.anexos (
  id            uuid primary key default gen_random_uuid(),
  fechamento_id uuid not null references public.fechamentos on delete cascade,
  saida_id      uuid references public.saidas on delete cascade,
  categoria     text not null,
  nome_arquivo  text not null,
  caminho       text not null,
  onedrive_id   text,
  criado_em     timestamptz not null default now()
);

create table if not exists public.conferencias (
  fechamento_id uuid primary key references public.fechamentos on delete cascade,
  conferido_por uuid references auth.users default auth.uid(),
  conferido_em  timestamptz not null default now(),
  nota          text
);

create table if not exists public.mapeamento_bc (
  lancamento text primary key,
  tipo text, conta text, cnpj text, nome text, forma text,
  categoria text, departamento text, status text default 'Pago', etiqueta text
);

-- Funções de acesso
create or replace function public.eh_escritorio() returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from perfis where user_id = auth.uid() and papel = 'escritorio') $$;

create or replace function public.meu_cliente() returns uuid
language sql stable security definer set search_path = public as
$$ select cliente_id from perfis where user_id = auth.uid() and papel = 'operador' $$;

-- Todo usuário novo ganha um perfil "pendente"; a conta da Carol já entra como escritório
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  insert into perfis(user_id, email, nome, papel)
  values (new.id, new.email, split_part(new.email,'@',1),
          case when lower(new.email) = 'controlacs@outlook.com' then 'escritorio' else 'pendente' end)
  on conflict (user_id) do nothing;
  return new;
end $$;
drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.novo_usuario();

insert into public.perfis(user_id, email, nome, papel)
select id, email, split_part(email,'@',1),
       case when lower(email) = 'controlacs@outlook.com' then 'escritorio' else 'pendente' end
from auth.users on conflict (user_id) do nothing;

-- Regras de acesso
alter table public.clientes      enable row level security;
alter table public.perfis        enable row level security;
alter table public.fechamentos   enable row level security;
alter table public.saidas        enable row level security;
alter table public.anexos        enable row level security;
alter table public.conferencias  enable row level security;
alter table public.mapeamento_bc enable row level security;

drop policy if exists esc_tudo on public.clientes;
create policy esc_tudo on public.clientes      for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.perfis;
create policy esc_tudo on public.perfis        for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.fechamentos;
create policy esc_tudo on public.fechamentos   for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.saidas;
create policy esc_tudo on public.saidas        for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.anexos;
create policy esc_tudo on public.anexos        for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.conferencias;
create policy esc_tudo on public.conferencias  for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.mapeamento_bc;
create policy esc_tudo on public.mapeamento_bc for all using (eh_escritorio()) with check (eh_escritorio());

drop policy if exists op_ver on public.perfis;
create policy op_ver on public.perfis   for select using (user_id = auth.uid());
drop policy if exists op_ver on public.clientes;
create policy op_ver on public.clientes for select using (id = meu_cliente());

drop policy if exists op_ver on public.fechamentos;
create policy op_ver    on public.fechamentos for select using (cliente_id = meu_cliente());
drop policy if exists op_criar on public.fechamentos;
create policy op_criar  on public.fechamentos for insert with check (cliente_id = meu_cliente() and not conferido);
drop policy if exists op_editar on public.fechamentos;
create policy op_editar on public.fechamentos for update
  using (cliente_id = meu_cliente() and not conferido)
  with check (cliente_id = meu_cliente() and not conferido);

drop policy if exists op_saidas on public.saidas;
create policy op_saidas on public.saidas for all
  using (exists(select 1 from fechamentos f where f.id = fechamento_id and f.cliente_id = meu_cliente() and not f.conferido))
  with check (exists(select 1 from fechamentos f where f.id = fechamento_id and f.cliente_id = meu_cliente() and not f.conferido));
drop policy if exists op_anexos on public.anexos;
create policy op_anexos on public.anexos for all
  using (exists(select 1 from fechamentos f where f.id = fechamento_id and f.cliente_id = meu_cliente() and not f.conferido))
  with check (exists(select 1 from fechamentos f where f.id = fechamento_id and f.cliente_id = meu_cliente() and not f.conferido));

-- Arquivos anexados (pasta = id do cliente)
insert into storage.buckets (id, name, public) values ('anexos','anexos', false)
on conflict (id) do nothing;
drop policy if exists anexos_esc on storage.objects;
create policy anexos_esc on storage.objects for all
  using (bucket_id = 'anexos' and public.eh_escritorio())
  with check (bucket_id = 'anexos' and public.eh_escritorio());
drop policy if exists anexos_op on storage.objects;
create policy anexos_op on storage.objects for all
  using (bucket_id = 'anexos' and (storage.foldername(name))[1] = public.meu_cliente()::text)
  with check (bucket_id = 'anexos' and (storage.foldername(name))[1] = public.meu_cliente()::text);

-- Dados iniciais
insert into public.clientes(nome) values ('Oliveira SJ') on conflict (nome) do nothing;

insert into public.mapeamento_bc(lancamento, tipo, conta, forma, categoria, status) values
 ('Venda em dinheiro','Receita','Caixa','Dinheiro','Receita de vendas','Pago'),
 ('Venda cartão de débito','Receita','Banco / adquirente','Cartão de débito','Receita de vendas','Pago'),
 ('Venda cartão de crédito','Receita','Banco / adquirente','Cartão de crédito','Receita de vendas','Pago'),
 ('Juros de parcelamento (crédito)','Receita','Banco / adquirente','Cartão de crédito','Juros de parcelamento','Pago'),
 ('Falta de caixa','Despesa','Caixa','Dinheiro','Quebra de caixa','Pago'),
 ('Sobra de caixa','Receita','Caixa','Dinheiro','Sobra de caixa','Pago'),
 ('Devolução em dinheiro','Despesa','Caixa','Dinheiro','Devoluções a clientes','Pago'),
 ('Repasse','Despesa','Caixa','Dinheiro','Repasses','Pago'),
 ('Água / voucher','Despesa','Caixa','Dinheiro','Água e copa','Pago'),
 ('Material de limpeza / higiene','Despesa','Caixa','Dinheiro','Material de limpeza','Pago'),
 ('Outras despesas pagas no caixa','Despesa','Caixa','Dinheiro','Outras despesas','Pago')
on conflict (lancamento) do nothing;


-- Permissões da API (projetos novos do Supabase podem não liberar automaticamente)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

notify pgrst, 'reload schema';
select 'Instalação concluída' as resultado;
