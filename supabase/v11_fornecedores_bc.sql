-- Portal do Cliente (Controlacs) - atualização v11: cadastro de fornecedores do Bom Controle (24/10/2026)
-- Rodar depois do v10_categoria_confirmada.sql. Pode rodar mais de uma vez.
-- O escritório importa a planilha de fornecedores exportada do Bom Controle (Configurações > Fornecedores).
-- Na conferência, cada lançamento é ligado a um fornecedor desse cadastro; a exportação usa o nome e o
-- CNPJ/CPF exatamente como estão no Bom Controle (nome diferente faz a importação falhar).
-- chave = CNPJ/CPF só com números ou, quando não tem documento, "nome:" + razão social normalizada.

create table if not exists public.fornecedores_bc (
  chave        text primary key,
  documento    text,
  razao_social text not null,
  fantasia     text,
  tipo         text,
  bloqueado    boolean not null default false,
  atualizado_em timestamptz not null default now()
);

alter table public.contas_pagar         add column if not exists fornecedor_bc text;
alter table public.cartao_notas         add column if not exists fornecedor_bc text;
alter table public.tesouraria           add column if not exists fornecedor_bc text;
alter table public.fornecedor_categoria add column if not exists fornecedor_bc text;

alter table public.fornecedores_bc enable row level security;
drop policy if exists esc_tudo on public.fornecedores_bc;
create policy esc_tudo on public.fornecedores_bc for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Só o escritório liga o fornecedor do Bom Controle (o que vier de outro usuário é ignorado)
create or replace function public.categoria_so_escritorio() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if not eh_escritorio() then
    if tg_op = 'INSERT' then new.categoria := null; new.categoria_ok := false; new.fornecedor_bc := null;
    else new.categoria := old.categoria; new.categoria_ok := old.categoria_ok; new.fornecedor_bc := old.fornecedor_bc; end if;
  end if;
  return new;
end $$;

select 'Atualização v11 (fornecedores do Bom Controle) concluída' as resultado;
