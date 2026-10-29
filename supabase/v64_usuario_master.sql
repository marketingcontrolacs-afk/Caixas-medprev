-- =====================================================================
-- v64 · Usuário master (só a Carol) e o que só ele acessa
-- =====================================================================
-- Rode no SQL Editor do Supabase, depois da v33, v36 e v37. Pode rodar mais de uma vez.
-- Pedido da Carol (29/10/2026): um usuário MASTER, que é só ela (controlacs@outlook.com), com acesso a tudo.
-- Os demais têm as permissões que ela escolher. Configurações, plano de contas e as regras das categorias
-- são só do master, "para não virar um banco de dados bagunçado".
--   O master é o tipo 'admin' (antes "Administração Controlacs"). Agora só pode existir um.
--   Quem mais estava como administração vira Operador Controlacs com todos os módulos (menos os do master).
--   A equipe continua LENDO o plano de contas, as regras e os acessos (os outros módulos usam),
--   mas só o master grava.

-- ---------- 1) um master só ----------
update public.perfis set tipo = 'equipe', admin = false, modulos_equipe = null
 where tipo = 'admin' and lower(email) <> 'controlacs@outlook.com';
update public.perfis set tipo = 'admin' where lower(email) = 'controlacs@outlook.com';
update public.perfis set admin = (tipo = 'admin') where admin is distinct from (tipo = 'admin');
create unique index if not exists perfis_um_master on public.perfis ((true)) where tipo = 'admin';

-- ---------- 2) só o master cadastra usuários e troca senhas ----------
create or replace function public.criar_usuario(p_email text, p_senha text, p_nome text, p_tipo text)
returns uuid
language plpgsql security definer set search_path = public, extensions, auth as
$$ declare
  em  text := lower(trim(p_email));
  uid uuid := gen_random_uuid();
begin
  if not eh_admin() then raise exception 'Só o master cadastra usuários'; end if;
  if p_tipo not in ('equipe','cliente','colaborador') then raise exception 'Tipo de usuário inválido (só existe um master)'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'E-mail inválido'; end if;
  if length(coalesce(p_senha,'')) < 6 then raise exception 'A senha precisa ter pelo menos 6 caracteres'; end if;
  if exists(select 1 from auth.users where lower(email) = em) then raise exception 'Já existe um usuário com este e-mail'; end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change, email_change_token_new)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
          crypt(p_senha, gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', jsonb_build_object('nome', p_nome), now(), now(),
          '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true),
          'email', now(), now(), now());

  insert into perfis(user_id, email, nome, papel) values (uid, em, coalesce(nullif(trim(p_nome),''), split_part(em,'@',1)), 'pendente')
  on conflict (user_id) do nothing;
  update perfis set nome = coalesce(nullif(trim(p_nome),''), nome), tipo = p_tipo where user_id = uid;
  return uid;
end $$;

create or replace function public.trocar_senha(p_user uuid, p_senha text) returns void
language plpgsql security definer set search_path = public, extensions, auth as
$$ begin
  if not eh_admin() then raise exception 'Só o master troca senhas'; end if;
  if length(coalesce(p_senha,'')) < 6 then raise exception 'A senha precisa ter pelo menos 6 caracteres'; end if;
  if not exists(select 1 from perfis where user_id = p_user) then raise exception 'Usuário não encontrado'; end if;
  update auth.users set encrypted_password = crypt(p_senha, gen_salt('bf')), updated_at = now() where id = p_user;
end $$;

revoke execute on function public.criar_usuario(text,text,text,text) from public, anon;
revoke execute on function public.trocar_senha(uuid,text) from public, anon;
grant execute on function public.criar_usuario(text,text,text,text) to authenticated;
grant execute on function public.trocar_senha(uuid,text) to authenticated;

-- ---------- 3) só o master muda tipos (o operador não libera mais pendentes) ----------
create or replace function public.perfil_tipo() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if tg_op = 'UPDATE' and (new.tipo is distinct from old.tipo or new.papel is distinct from old.papel or new.admin is distinct from old.admin)
     and auth.uid() is not null and not eh_admin() then
    raise exception 'Só o master muda o tipo de usuário';
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

-- ---------- 4) plano de contas, regras e acessos: a equipe lê, só o master grava ----------
do $$ declare t text;
begin
  foreach t in array array['plano_contas','categoria_regras','fin_plano','fornecedores_bc','acessos'] loop
    if to_regclass('public.'||t) is null then continue; end if;
    execute format('drop policy if exists esc_tudo on public.%I', t);
    execute format('drop policy if exists esc_ler on public.%I', t);
    execute format('drop policy if exists master_grava on public.%I', t);
    execute format('create policy esc_ler on public.%I for select using (eh_escritorio())', t);
    execute format('create policy master_grava on public.%I for all using (eh_admin()) with check (eh_admin())', t);
  end loop;
end $$;

grant execute on all functions in schema public to authenticated;
notify pgrst, 'reload schema';

select coalesce(tipo,'pendente') as tipo, count(*) as usuarios, string_agg(coalesce(nome,email), ', ') as quem
from public.perfis group by 1 order by 1;
