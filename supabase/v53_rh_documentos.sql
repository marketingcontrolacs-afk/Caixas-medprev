-- =====================================================================
-- v53 · RH › Documentos: termos prontos com os dados da empresa e do colaborador
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez e não depende da ordem dos outros arquivos.
-- Pedido da Carol (28/10/2026): guardar os modelos de documentos (termos da Viva), escolher a empresa e o
-- colaborador, completar o que falta e gerar o PDF. Os dados da empresa trocam junto com a empresa.
--  1. CPF e setor no cadastro do colaborador (o cargo já existe e vale como função).
--  2. Dados da empresa para os documentos: razão social, unidade, cidade e a vigência do banco de horas.
--  3. Histórico dos documentos gerados, para imprimir de novo.

alter table public.funcionarios add column if not exists cpf   text;
alter table public.funcionarios add column if not exists setor text;

alter table public.clientes add column if not exists doc_empresa jsonb not null default '{}'::jsonb;

update public.clientes
   set cnpj = '35.966.515/0001-25',
       doc_empresa = doc_empresa || '{"razao": "CLÍNICA VIVA SIMON LTDA", "unidade": "Matriz", "cidade": "Florianópolis", "uf": "SC", "bh_ini": "2026-07-01", "bh_fim": "2026-12-31"}'::jsonb
 where nome = 'Clinica Viva Simon Matriz';
update public.clientes
   set cnpj = '35.966.515/0002-06',
       doc_empresa = doc_empresa || '{"razao": "CLÍNICA VIVA SIMON LTDA", "unidade": "Filial", "cidade": "Florianópolis", "uf": "SC", "bh_ini": "2026-01-01", "bh_fim": "2026-06-30"}'::jsonb
 where nome = 'Clinica Simon Filial';

create table if not exists public.rh_documentos (
  id             uuid primary key default gen_random_uuid(),
  cliente_id     uuid not null references public.clientes on delete cascade,
  funcionario_id uuid references public.funcionarios on delete set null,
  modelo         text not null,
  nome           text,                                 -- nome do colaborador no documento
  dados          jsonb not null default '{}'::jsonb,   -- o que foi preenchido, para gerar de novo
  criado_por     uuid default auth.uid(),
  criado_em      timestamptz not null default now()
);
create index if not exists rh_documentos_cli on public.rh_documentos(cliente_id, criado_em desc);

alter table public.rh_documentos enable row level security;
drop policy if exists esc_tudo on public.rh_documentos;
create policy esc_tudo on public.rh_documentos for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.rh_documentos;
create policy op_ver on public.rh_documentos for select using (pode_ver(cliente_id,'colab'));
drop policy if exists op_gravar on public.rh_documentos;
create policy op_gravar on public.rh_documentos for insert with check (pode_lancar(cliente_id,'colab'));

select 'Atualização v53 (RH › Documentos) concluída' as resultado;
