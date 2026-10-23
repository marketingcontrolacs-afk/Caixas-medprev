-- Portal do Cliente (Controlacs) - atualização v2 (23/10/2026)
-- Rodar depois do schema.sql (v1). Pode rodar mais de uma vez.
-- Acessos por empresa e módulo: cada usuário recebe, por empresa, os módulos que usa
-- e o nível em cada um (lancamento = lança e corrige; consulta = só vê).
-- Escritório continua vendo e fazendo tudo.
-- Módulos novos: Contas a pagar, Cartão de crédito e Tesouraria, com documentos anexados.

alter table public.perfis drop constraint if exists perfis_papel_check;
alter table public.perfis add constraint perfis_papel_check check (papel in ('pendente','operador','escritorio'));

alter table public.clientes add column if not exists tem_cartao   boolean not null default false;
alter table public.clientes add column if not exists cartao_final text;

create table if not exists public.acessos (
  user_id    uuid not null references auth.users on delete cascade,
  cliente_id uuid not null references public.clientes on delete cascade,
  modulo     text not null check (modulo in ('caixa','pagar','cartao','tesouraria')),
  nivel      text not null check (nivel in ('lancamento','consulta')),
  primary key (user_id, cliente_id, modulo)
);

-- Quem já era operador de caixa de um cliente passa a ter "caixa / lançamento" nele
insert into public.acessos(user_id, cliente_id, modulo, nivel)
select user_id, cliente_id, 'caixa', 'lancamento' from public.perfis
where papel = 'operador' and cliente_id is not null
on conflict do nothing;

create table if not exists public.contas_pagar (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes,
  fornecedor  text not null,
  documento   text not null,
  vencimento  date not null,
  valor       numeric(12,2) not null check (valor > 0),
  obs         text,
  enviado_por uuid references auth.users default auth.uid(),
  enviado_em  timestamptz not null default now(),
  conferido   boolean not null default false,   -- aqui significa "paga"
  pago_em     date,
  banco       text
);

create table if not exists public.cartao_notas (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes,
  data        date not null,
  fornecedor  text not null,
  documento   text not null,
  valor       numeric(12,2) not null check (valor > 0),
  parcelas    int not null default 1 check (parcelas between 1 and 24),
  obs         text,
  enviado_por uuid references auth.users default auth.uid(),
  enviado_em  timestamptz not null default now(),
  conferido   boolean not null default false    -- conferido com a fatura
);

create table if not exists public.tesouraria (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes,
  data        date not null,
  tipo        text not null check (tipo in ('Despesa','Suprimento')),
  descricao   text not null,
  documento   text,
  valor       numeric(12,2) not null check (valor > 0),
  obs         text,
  enviado_por uuid references auth.users default auth.uid(),
  enviado_em  timestamptz not null default now(),
  conferido   boolean not null default false
);

-- Documentos dos módulos novos (o caixa continua usando a tabela anexos)
create table if not exists public.documentos (
  id           uuid primary key default gen_random_uuid(),
  cliente_id   uuid not null references public.clientes,
  modulo       text not null check (modulo in ('pagar','cartao','tesouraria')),
  registro_id  uuid not null,
  categoria    text not null,
  nome_arquivo text not null,
  caminho      text not null,
  onedrive_id  text,
  enviado_por  uuid references auth.users default auth.uid(),
  criado_em    timestamptz not null default now()
);
create index if not exists documentos_registro on public.documentos(registro_id);

-- Funções de acesso
create or replace function public.pode_ver(cli uuid, mod text) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_escritorio() or exists(select 1 from acessos where user_id = auth.uid() and cliente_id = cli and modulo = mod) $$;

create or replace function public.pode_lancar(cli uuid, mod text) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_escritorio() or exists(select 1 from acessos where user_id = auth.uid() and cliente_id = cli and modulo = mod and nivel = 'lancamento') $$;

-- Registro ainda aberto (não pago / não conferido)? Usado nas regras dos documentos.
create or replace function public.registro_aberto(mod text, reg uuid) returns boolean
language plpgsql stable security definer set search_path = public as
$$ declare r boolean;
begin
  if mod = 'pagar' then select not conferido into r from contas_pagar where id = reg;
  elsif mod = 'cartao' then select not conferido into r from cartao_notas where id = reg;
  elsif mod = 'tesouraria' then select not conferido into r from tesouraria where id = reg;
  end if;
  return coalesce(r, true);
end $$;

-- Ao apagar um lançamento, apaga os documentos ligados a ele
create or replace function public.apagar_documentos() returns trigger
language plpgsql security definer set search_path = public as
$$ begin delete from documentos where registro_id = old.id; return old; end $$;
drop trigger if exists apaga_docs on public.contas_pagar;
create trigger apaga_docs after delete on public.contas_pagar for each row execute function public.apagar_documentos();
drop trigger if exists apaga_docs on public.cartao_notas;
create trigger apaga_docs after delete on public.cartao_notas for each row execute function public.apagar_documentos();
drop trigger if exists apaga_docs on public.tesouraria;
create trigger apaga_docs after delete on public.tesouraria for each row execute function public.apagar_documentos();

-- Regras de acesso
alter table public.acessos      enable row level security;
alter table public.contas_pagar enable row level security;
alter table public.cartao_notas enable row level security;
alter table public.tesouraria   enable row level security;
alter table public.documentos   enable row level security;

drop policy if exists esc_tudo on public.acessos;
create policy esc_tudo on public.acessos for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists meus on public.acessos;
create policy meus on public.acessos for select using (user_id = auth.uid());

-- Empresas: cada um vê as que tem liberadas
drop policy if exists op_ver on public.clientes;
create policy op_ver on public.clientes for select
  using (exists(select 1 from acessos a where a.user_id = auth.uid() and a.cliente_id = clientes.id));

-- Caixa (v1 usava o cliente do perfil; agora usa os acessos)
drop policy if exists op_ver on public.fechamentos;
create policy op_ver    on public.fechamentos for select using (pode_ver(cliente_id,'caixa'));
drop policy if exists op_criar on public.fechamentos;
create policy op_criar  on public.fechamentos for insert with check (pode_lancar(cliente_id,'caixa') and not conferido);
drop policy if exists op_editar on public.fechamentos;
create policy op_editar on public.fechamentos for update
  using (pode_lancar(cliente_id,'caixa') and not conferido)
  with check (pode_lancar(cliente_id,'caixa') and not conferido);

drop policy if exists op_saidas on public.saidas;
drop policy if exists op_ver_saidas on public.saidas;
create policy op_ver_saidas on public.saidas for select
  using (exists(select 1 from fechamentos f where f.id = fechamento_id and pode_ver(f.cliente_id,'caixa')));
drop policy if exists op_gravar_saidas on public.saidas;
create policy op_gravar_saidas on public.saidas for all
  using (exists(select 1 from fechamentos f where f.id = fechamento_id and pode_lancar(f.cliente_id,'caixa') and not f.conferido))
  with check (exists(select 1 from fechamentos f where f.id = fechamento_id and pode_lancar(f.cliente_id,'caixa') and not f.conferido));

drop policy if exists op_anexos on public.anexos;
drop policy if exists op_ver_anexos on public.anexos;
create policy op_ver_anexos on public.anexos for select
  using (exists(select 1 from fechamentos f where f.id = fechamento_id and pode_ver(f.cliente_id,'caixa')));
drop policy if exists op_gravar_anexos on public.anexos;
create policy op_gravar_anexos on public.anexos for all
  using (exists(select 1 from fechamentos f where f.id = fechamento_id and pode_lancar(f.cliente_id,'caixa') and not f.conferido))
  with check (exists(select 1 from fechamentos f where f.id = fechamento_id and pode_lancar(f.cliente_id,'caixa') and not f.conferido));

-- Módulos novos: ver com qualquer acesso; lançar, corrigir e apagar só com "lançamento" e enquanto aberto
drop policy if exists esc_tudo on public.contas_pagar;
create policy esc_tudo on public.contas_pagar for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.contas_pagar;
create policy op_ver on public.contas_pagar for select using (pode_ver(cliente_id,'pagar'));
drop policy if exists op_criar on public.contas_pagar;
create policy op_criar on public.contas_pagar for insert with check (pode_lancar(cliente_id,'pagar') and not conferido);
drop policy if exists op_editar on public.contas_pagar;
create policy op_editar on public.contas_pagar for update
  using (pode_lancar(cliente_id,'pagar') and not conferido) with check (pode_lancar(cliente_id,'pagar') and not conferido);
drop policy if exists op_apagar on public.contas_pagar;
create policy op_apagar on public.contas_pagar for delete using (pode_lancar(cliente_id,'pagar') and not conferido);

drop policy if exists esc_tudo on public.cartao_notas;
create policy esc_tudo on public.cartao_notas for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.cartao_notas;
create policy op_ver on public.cartao_notas for select using (pode_ver(cliente_id,'cartao'));
drop policy if exists op_criar on public.cartao_notas;
create policy op_criar on public.cartao_notas for insert with check (pode_lancar(cliente_id,'cartao') and not conferido);
drop policy if exists op_editar on public.cartao_notas;
create policy op_editar on public.cartao_notas for update
  using (pode_lancar(cliente_id,'cartao') and not conferido) with check (pode_lancar(cliente_id,'cartao') and not conferido);
drop policy if exists op_apagar on public.cartao_notas;
create policy op_apagar on public.cartao_notas for delete using (pode_lancar(cliente_id,'cartao') and not conferido);

drop policy if exists esc_tudo on public.tesouraria;
create policy esc_tudo on public.tesouraria for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.tesouraria;
create policy op_ver on public.tesouraria for select using (pode_ver(cliente_id,'tesouraria'));
drop policy if exists op_criar on public.tesouraria;
create policy op_criar on public.tesouraria for insert with check (pode_lancar(cliente_id,'tesouraria') and not conferido);
drop policy if exists op_editar on public.tesouraria;
create policy op_editar on public.tesouraria for update
  using (pode_lancar(cliente_id,'tesouraria') and not conferido) with check (pode_lancar(cliente_id,'tesouraria') and not conferido);
drop policy if exists op_apagar on public.tesouraria;
create policy op_apagar on public.tesouraria for delete using (pode_lancar(cliente_id,'tesouraria') and not conferido);

drop policy if exists esc_tudo on public.documentos;
create policy esc_tudo on public.documentos for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.documentos;
create policy op_ver on public.documentos for select using (pode_ver(cliente_id, modulo));
drop policy if exists op_gravar on public.documentos;
create policy op_gravar on public.documentos for all
  using (pode_lancar(cliente_id, modulo) and registro_aberto(modulo, registro_id))
  with check (pode_lancar(cliente_id, modulo) and registro_aberto(modulo, registro_id));

-- Arquivos: <cliente>/<data>/... é do caixa; <cliente>/<modulo>/... é do módulo
create or replace function public.modulo_do_arquivo(nome text) returns text
language sql immutable as
$$ select case when (string_to_array(nome,'/'))[2] in ('pagar','cartao','tesouraria') then (string_to_array(nome,'/'))[2] else 'caixa' end $$;

drop policy if exists anexos_op on storage.objects;
drop policy if exists anexos_ver on storage.objects;
create policy anexos_ver on storage.objects for select
  using (bucket_id = 'anexos' and public.pode_ver(((storage.foldername(name))[1])::uuid, public.modulo_do_arquivo(name)));
drop policy if exists anexos_enviar on storage.objects;
create policy anexos_enviar on storage.objects for insert
  with check (bucket_id = 'anexos' and public.pode_lancar(((storage.foldername(name))[1])::uuid, public.modulo_do_arquivo(name)));

grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

notify pgrst, 'reload schema';
select 'Atualização v2 concluída' as resultado;
