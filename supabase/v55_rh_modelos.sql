-- =====================================================================
-- v55 · RH › Documentos: modelos próprios importados do Word
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez e não depende da ordem dos outros arquivos.
-- Pedido da Carol (28/10/2026): importar o modelo em Word com marcações como {nome}, {cpf} e {data};
-- o sistema troca as marcações pelos dados do colaborador e da empresa e gera o PDF.

create table if not exists public.rh_modelos (
  id         uuid primary key default gen_random_uuid(),
  cliente_id uuid references public.clientes on delete cascade,   -- vazio = todas as empresas
  nome       text not null,
  html       text not null,                                         -- o documento convertido do Word
  arquivo    text,                                                  -- nome do arquivo importado
  criado_por uuid default auth.uid(),
  criado_em  timestamptz not null default now()
);
create index if not exists rh_modelos_cli on public.rh_modelos(cliente_id);

alter table public.rh_modelos enable row level security;
drop policy if exists esc_tudo on public.rh_modelos;
create policy esc_tudo on public.rh_modelos for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.rh_modelos;
create policy op_ver on public.rh_modelos for select
  using (cliente_id is null and exists (select 1 from public.acessos a where a.user_id = auth.uid() and a.modulo in ('colab','folha','ferias'))
         or cliente_id is not null and pode_ver(cliente_id,'colab'));

select 'Atualização v55 (modelos de documentos do Word) concluída' as resultado;
