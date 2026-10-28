-- =====================================================================
-- v56 · Dados das 3 Oliveira para os documentos (carta da conta salário Santander)
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v53. Pode rodar mais de uma vez; não troca o que já foi preenchido.
-- Dados dos cartões CNPJ enviados pela Carol (28/10/2026).

update public.clientes
   set cnpj = coalesce(nullif(cnpj,''), '23.828.773/0001-66'),
       doc_empresa = '{"razao": "Oliveira e Schmidt Apoio Administrativo Ltda", "unidade": "Matriz", "cidade": "São José", "uf": "SC"}'::jsonb || coalesce(doc_empresa,'{}'::jsonb)
 where nome = 'Oliveira SJ';
update public.clientes
   set cnpj = coalesce(nullif(cnpj,''), '23.828.773/0002-47'),
       doc_empresa = '{"razao": "Oliveira e Schmidt Apoio Administrativo Ltda", "unidade": "Filial", "cidade": "Palhoça", "uf": "SC"}'::jsonb || coalesce(doc_empresa,'{}'::jsonb)
 where nome = 'Oliveira Palhoça';
update public.clientes
   set cnpj = coalesce(nullif(cnpj,''), '23.828.773/0003-28'),
       doc_empresa = '{"razao": "Oliveira e Schmidt Apoio Administrativo Ltda", "unidade": "Filial", "cidade": "Biguaçu", "uf": "SC"}'::jsonb || coalesce(doc_empresa,'{}'::jsonb)
 where nome = 'Oliveira Biguaçu';

select 'Atualização v56 (dados das Oliveira) concluída' as resultado;
