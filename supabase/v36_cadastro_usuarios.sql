-- =====================================================================
-- v36 · Cadastro de usuários pelo portal (sem entrar no Supabase)
-- =====================================================================
-- Rode no SQL Editor do Supabase, depois da v33. Pode rodar mais de uma vez.
-- Pedido da Carol (26/10/2026): botão "Novo usuário" em Configurações, com e-mail, senha, nome e tipo,
-- e "Trocar senha" para quem esqueceu.
--   A administradora cadastra qualquer tipo. O operador Controlacs cadastra só cliente e colaborador.
--   O login já nasce confirmado (pode entrar na hora com a senha informada).

create extension if not exists pgcrypto with schema extensions;

create or replace function public.criar_usuario(p_email text, p_senha text, p_nome text, p_tipo text)
returns uuid
language plpgsql security definer set search_path = public, extensions, auth as
$$ declare
  em  text := lower(trim(p_email));
  uid uuid := gen_random_uuid();
begin
  if not eh_escritorio() then raise exception 'Só o escritório cadastra usuários'; end if;
  if p_tipo not in ('admin','equipe','cliente','colaborador') then raise exception 'Tipo de usuário inválido'; end if;
  if p_tipo in ('admin','equipe') and not eh_admin() then raise exception 'Só a administradora cadastra usuários da equipe'; end if;
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

  -- o perfil nasce "pendente" pelo gatilho do cadastro; aqui ganha o nome e o tipo
  insert into perfis(user_id, email, nome, papel) values (uid, em, coalesce(nullif(trim(p_nome),''), split_part(em,'@',1)), 'pendente')
  on conflict (user_id) do nothing;
  update perfis set nome = coalesce(nullif(trim(p_nome),''), nome), tipo = p_tipo where user_id = uid;
  return uid;
end $$;

create or replace function public.trocar_senha(p_user uuid, p_senha text) returns void
language plpgsql security definer set search_path = public, extensions, auth as
$$ declare alvo perfis;
begin
  if not eh_escritorio() then raise exception 'Só o escritório troca senhas'; end if;
  if length(coalesce(p_senha,'')) < 6 then raise exception 'A senha precisa ter pelo menos 6 caracteres'; end if;
  select * into alvo from perfis where user_id = p_user;
  if not found then raise exception 'Usuário não encontrado'; end if;
  if alvo.papel = 'escritorio' and not eh_admin() then raise exception 'Só a administradora troca a senha da equipe'; end if;
  update auth.users set encrypted_password = crypt(p_senha, gen_salt('bf')), updated_at = now() where id = p_user;
end $$;

revoke execute on function public.criar_usuario(text,text,text,text) from public, anon;
revoke execute on function public.trocar_senha(uuid,text) from public, anon;
grant execute on function public.criar_usuario(text,text,text,text) to authenticated;
grant execute on function public.trocar_senha(uuid,text) to authenticated;

notify pgrst, 'reload schema';

select 'Cadastro de usuários pelo portal instalado' as resultado;
