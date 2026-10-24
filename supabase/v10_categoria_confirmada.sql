-- Portal do Cliente (Controlacs) - atualização v10: código no plano de contas e categoria confirmada pelo escritório (24/10/2026)
-- Rodar depois do v9_plano_rateio.sql. Pode rodar mais de uma vez.
-- O cliente não escolhe categoria: nas contas a pagar e no cartão ele informa "do que se trata" a despesa
-- (na tesouraria vale a descrição). O sistema sugere a categoria e o escritório confirma; só o que foi
-- confirmado entra na exportação do Bom Controle.

alter table public.plano_contas add column if not exists codigo text;

alter table public.contas_pagar add column if not exists sobre        text;
alter table public.cartao_notas add column if not exists sobre        text;
alter table public.tesouraria   add column if not exists categoria    text;
alter table public.contas_pagar add column if not exists categoria_ok boolean not null default false;
alter table public.cartao_notas add column if not exists categoria_ok boolean not null default false;
alter table public.tesouraria   add column if not exists categoria_ok boolean not null default false;

-- Categoria escolhida antes desta atualização conta como confirmada (só o escritório via esse campo)
update public.contas_pagar set categoria_ok = true where categoria is not null and not categoria_ok;
update public.cartao_notas set categoria_ok = true where categoria is not null and not categoria_ok;

-- Só o escritório grava categoria: o que vier de outro usuário é ignorado
create or replace function public.categoria_so_escritorio() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if not eh_escritorio() then
    if tg_op = 'INSERT' then new.categoria := null; new.categoria_ok := false;
    else new.categoria := old.categoria; new.categoria_ok := old.categoria_ok; end if;
  end if;
  return new;
end $$;
drop trigger if exists categoria_escritorio on public.contas_pagar;
create trigger categoria_escritorio before insert or update on public.contas_pagar for each row execute function public.categoria_so_escritorio();
drop trigger if exists categoria_escritorio on public.cartao_notas;
create trigger categoria_escritorio before insert or update on public.cartao_notas for each row execute function public.categoria_so_escritorio();
drop trigger if exists categoria_escritorio on public.tesouraria;
create trigger categoria_escritorio before insert or update on public.tesouraria for each row execute function public.categoria_so_escritorio();

select 'Atualização v10 (categoria confirmada) concluída' as resultado;
