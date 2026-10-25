-- =====================================================================
-- v33 · Tipo de usuário + quem vê as tarefas + Avisos e notícias
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Já inclui a v31 e a v32 inteiras:
-- quem ainda não rodou essas duas roda só esta.
-- Pedido da Carol (25/10/2026): no cadastro de usuários, o tipo de cada um:
--   admin       = Administradora Controlacs (vê tudo)
--   equipe      = Operador Controlacs
--   cliente     = Cliente (gestor da empresa)
--   colaborador = Colaborador do cliente
-- Os níveis de permissão (Lançamento / Consulta, por empresa e módulo) continuam em Acessos.

-- ---------- 1) quem vê cada tarefa ----------
create table if not exists public.tarefa_usuarios (
  tarefa_id uuid not null references public.tarefas on delete cascade,
  user_id   uuid not null references auth.users on delete cascade,
  primary key (tarefa_id, user_id)
);
alter table public.tarefa_usuarios enable row level security;
drop policy if exists esc_tudo on public.tarefa_usuarios;
create policy esc_tudo on public.tarefa_usuarios for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists meu on public.tarefa_usuarios;
create policy meu on public.tarefa_usuarios for select using (user_id = auth.uid());

-- Tarefa liberada para quem está logado: ninguém marcado (vale para todos) ou ele está marcado
create or replace function public.tarefa_liberada(t uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_escritorio()
       or not exists(select 1 from tarefa_usuarios where tarefa_id = t)
       or exists(select 1 from tarefa_usuarios where tarefa_id = t and user_id = auth.uid()) $$;

create or replace function public.ve_tarefa(t uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_escritorio() or exists(select 1 from tarefas where id = t and not interna and cliente_id is not null
                                     and pode_ver(cliente_id,'tarefas') and tarefa_liberada(t)) $$;

drop policy if exists op_ver on public.tarefas;
create policy op_ver on public.tarefas for select using (not interna and pode_ver(cliente_id,'tarefas') and tarefa_liberada(id));
drop policy if exists op_mover on public.tarefas;
create policy op_mover on public.tarefas for update
  using (not interna and pode_lancar(cliente_id,'tarefas') and tarefa_liberada(id)) with check (pode_lancar(cliente_id,'tarefas'));

-- ---------- 2) avisos e notícias ----------
create table if not exists public.avisos (
  id              uuid primary key default gen_random_uuid(),
  titulo          text not null,
  texto           text,
  publico         text not null default 'todos' check (publico in ('todos','clientes','equipe','selecionados')),
  importante      boolean not null default false,   -- fica no topo, destacado
  expira_em       date,                             -- depois desta data some para os usuários
  anexo_caminho   text,
  anexo_nome      text,
  criado_por      uuid references auth.users default auth.uid(),
  criado_por_nome text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create table if not exists public.aviso_usuarios (
  aviso_id uuid not null references public.avisos on delete cascade,
  user_id  uuid not null references auth.users on delete cascade,
  primary key (aviso_id, user_id)
);
create table if not exists public.aviso_leituras (
  aviso_id uuid not null references public.avisos on delete cascade,
  user_id  uuid not null references auth.users on delete cascade default auth.uid(),
  lido_em  timestamptz not null default now(),
  primary key (aviso_id, user_id)
);

create or replace function public.aviso_antes() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if tg_op = 'INSERT' then new.criado_por_nome := nome_usuario(new.criado_por); end if;
  new.atualizado_em := now();
  return new;
end $$;
drop trigger if exists aviso_antes on public.avisos;
create trigger aviso_antes before insert or update on public.avisos
  for each row execute function public.aviso_antes();

-- Aviso que o usuário logado pode ler
create or replace function public.ve_aviso(a uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_escritorio() or exists(
     select 1 from avisos v where v.id = a and (v.expira_em is null or v.expira_em >= current_date) and (
       v.publico = 'todos'
       or (v.publico = 'clientes' and exists(select 1 from perfis where user_id = auth.uid() and papel = 'operador'))
       or (v.publico = 'selecionados' and exists(select 1 from aviso_usuarios where aviso_id = a and user_id = auth.uid()))
     )) $$;

alter table public.avisos         enable row level security;
alter table public.aviso_usuarios enable row level security;
alter table public.aviso_leituras enable row level security;
drop policy if exists esc_tudo on public.avisos;
create policy esc_tudo on public.avisos for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists ler on public.avisos;
create policy ler on public.avisos for select using (ve_aviso(id));
drop policy if exists esc_tudo on public.aviso_usuarios;
create policy esc_tudo on public.aviso_usuarios for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists meu on public.aviso_leituras;
create policy meu on public.aviso_leituras for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists esc_ver on public.aviso_leituras;
create policy esc_ver on public.aviso_leituras for select using (eh_escritorio());

-- Avisos ainda não lidos por quem está logado
create or replace function public.avisos_nao_lidos() returns bigint
language sql stable set search_path = public as
$$ select count(*) from avisos v
   where (v.expira_em is null or v.expira_em >= current_date) and v.criado_por is distinct from auth.uid()
     -- a equipe enxerga todos os avisos, mas só conta os que são para ela
     and (not eh_escritorio() or v.publico in ('todos','equipe')
          or exists(select 1 from aviso_usuarios u where u.aviso_id = v.id and u.user_id = auth.uid()))
     and not exists(select 1 from aviso_leituras l where l.aviso_id = v.id and l.user_id = auth.uid()) $$;

-- Anexo do aviso: pasta 00000000-0000-0000-0000-000000000000/avisos/...; lê quem pode ler o aviso
create or replace function public.anexo_de_aviso_liberado(nome text) returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from avisos where anexo_caminho = nome and ve_aviso(id)) $$;
drop policy if exists avisos_ver on storage.objects;
create policy avisos_ver on storage.objects for select
  using (bucket_id = 'anexos' and (storage.foldername(name))[2] = 'avisos' and public.anexo_de_aviso_liberado(name));

grant select, insert, update, delete on public.tarefa_usuarios, public.avisos, public.aviso_usuarios, public.aviso_leituras to authenticated;
grant execute on all functions in schema public to authenticated;

-- ---------- v32: administradora e equipe ----------
alter table public.perfis add column if not exists admin boolean not null default false;
update public.perfis set admin = true where lower(email) = 'controlacs@outlook.com';

-- Administradora: vê todas as tarefas, mesmo as que não foram liberadas para ela
create or replace function public.eh_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from perfis where user_id = auth.uid() and papel = 'escritorio' and admin) $$;

-- Tarefa liberada para quem está logado: administradora, ninguém marcado (vale para todos),
-- marcado na lista, quem abriu ou o responsável
create or replace function public.tarefa_liberada(t uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_admin()
       or not exists(select 1 from tarefa_usuarios where tarefa_id = t)
       or exists(select 1 from tarefa_usuarios where tarefa_id = t and user_id = auth.uid())
       or exists(select 1 from tarefas where id = t and auth.uid() in (criado_por, responsavel)) $$;

create or replace function public.ve_tarefa(t uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select (eh_escritorio() and tarefa_liberada(t))
       or exists(select 1 from tarefas where id = t and not interna and cliente_id is not null
                  and pode_ver(cliente_id,'tarefas') and tarefa_liberada(t)) $$;

-- A equipe só vê, move e comenta as tarefas liberadas para ela; cria qualquer tarefa
drop policy if exists esc_tudo on public.tarefas;
drop policy if exists esc_criar on public.tarefas;
create policy esc_criar on public.tarefas for insert with check (eh_escritorio());
drop policy if exists esc_liberadas on public.tarefas;
create policy esc_liberadas on public.tarefas for all
  using (eh_escritorio() and tarefa_liberada(id)) with check (eh_escritorio());

drop policy if exists esc_tudo on public.tarefa_comentarios;
create policy esc_tudo on public.tarefa_comentarios for all
  using (eh_escritorio() and tarefa_liberada(tarefa_id)) with check (eh_escritorio() and tarefa_liberada(tarefa_id));

grant execute on all functions in schema public to authenticated;

-- ---------- v33: tipo de usuário ----------
alter table public.perfis add column if not exists tipo text;
alter table public.perfis drop constraint if exists perfis_tipo_check;
alter table public.perfis add constraint perfis_tipo_check check (tipo in ('admin','equipe','cliente','colaborador'));
update public.perfis set tipo = case when papel = 'escritorio' and admin then 'admin' when papel = 'escritorio' then 'equipe' else 'cliente' end
 where tipo is null and papel <> 'pendente';

-- O tipo decide o papel (regras de acesso) e a administração; só a administradora troca tipos
create or replace function public.perfil_tipo() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if tg_op = 'UPDATE' and (new.tipo is distinct from old.tipo or new.papel is distinct from old.papel or new.admin is distinct from old.admin)
     and auth.uid() is not null and not eh_admin() then
    -- o operador Controlacs só pode liberar quem está pendente como usuário de cliente
    if not (old.papel = 'pendente' and coalesce(new.tipo,'cliente') in ('cliente','colaborador')) then
      raise exception 'Só a administradora muda o tipo de usuário';
    end if;
  end if;
  if tg_op = 'INSERT' and lower(new.email) = 'controlacs@outlook.com' then new.tipo := 'admin'; end if;
  if tg_op = 'INSERT' or new.tipo is distinct from old.tipo then
    new.papel := case when new.tipo in ('admin','equipe') then 'escritorio' when new.tipo in ('cliente','colaborador') then 'operador' else coalesce(new.papel,'pendente') end;
  end if;
  if new.tipo is null and new.papel = 'operador' then new.tipo := 'cliente'; end if;
  if new.tipo is null and new.papel = 'escritorio' then new.tipo := 'equipe'; end if;
  new.admin := coalesce(new.tipo = 'admin', false);
  return new;
end $$;
drop trigger if exists perfil_tipo on public.perfis;
create trigger perfil_tipo before insert or update on public.perfis
  for each row execute function public.perfil_tipo();
update public.perfis set tipo = 'admin' where lower(email) = 'controlacs@outlook.com';

grant execute on all functions in schema public to authenticated;

notify pgrst, 'reload schema';

select coalesce(tipo,'pendente') as tipo, count(*) as usuarios, string_agg(coalesce(nome,email), ', ') as quem
from public.perfis group by 1 order by 1;
