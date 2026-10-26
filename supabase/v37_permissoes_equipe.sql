-- =====================================================================
-- v37 · Permissões de cada Operador Controlacs
-- =====================================================================
-- Rode no SQL Editor do Supabase, depois da v33. Pode rodar mais de uma vez.
-- Pedido da Carol (26/10/2026): escolher, um por um, os módulos e as empresas que cada Operador Controlacs
-- vê no menu. Tarefas e Avisos ficam sempre liberados para toda a equipe.
--   modulos_equipe  vazio (null) = todos os módulos; senão, só os marcados (chaves do menu do portal)
--   empresas_equipe vazio (null) = todas as empresas; senão, só as marcadas
-- Só a administradora muda essas permissões.

alter table public.perfis add column if not exists modulos_equipe text[];
alter table public.perfis add column if not exists empresas_equipe uuid[];

create or replace function public.perfil_permissoes() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if (new.modulos_equipe is distinct from old.modulos_equipe or new.empresas_equipe is distinct from old.empresas_equipe)
     and auth.uid() is not null and not eh_admin() then
    raise exception 'Só a administradora muda as permissões da equipe';
  end if;
  return new;
end $$;
drop trigger if exists perfil_permissoes on public.perfis;
create trigger perfil_permissoes before update on public.perfis
  for each row execute function public.perfil_permissoes();

notify pgrst, 'reload schema';

select 'Permissões da equipe instaladas' as resultado,
       (select count(*) from public.perfis where tipo = 'equipe') as operadores_controlacs;
