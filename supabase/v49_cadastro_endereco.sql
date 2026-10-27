-- =====================================================================
-- v49 · Gestão financeira: endereço e situação na Receita no cadastro de clientes e fornecedores
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v48. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): ao digitar o CNPJ, puxar os dados da Receita e mostrar se a empresa
-- está ativa ou baixada; ao digitar o CEP, puxar o endereço dos Correios.

alter table public.fin_pessoas add column if not exists cep              text;
alter table public.fin_pessoas add column if not exists endereco         text;
alter table public.fin_pessoas add column if not exists numero           text;
alter table public.fin_pessoas add column if not exists complemento      text;
alter table public.fin_pessoas add column if not exists bairro           text;
alter table public.fin_pessoas add column if not exists uf               text;
alter table public.fin_pessoas add column if not exists situacao_receita text;   -- ATIVA, BAIXADA, INAPTA, SUSPENSA...
alter table public.fin_pessoas add column if not exists situacao_em      date;   -- quando foi consultada

select 'Atualização v49 (endereço e situação na Receita) concluída' as resultado;
