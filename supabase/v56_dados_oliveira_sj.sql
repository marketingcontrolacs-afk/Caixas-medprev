-- =====================================================================
-- v56 · Dados da Oliveira SJ para os documentos (carta da conta salário Santander)
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v53. Pode rodar mais de uma vez; não troca o que já foi preenchido.
-- Biguaçu e Palhoça: preencher em RH › Documentos › "Alterar" (dados da empresa).

update public.clientes
   set cnpj = coalesce(nullif(cnpj,''), '23.828.773/0001-66'),
       doc_empresa = '{"razao": "Oliveira e Schmidt Apoio Administrativo Ltda", "cidade": "São José", "uf": "SC"}'::jsonb || coalesce(doc_empresa,'{}'::jsonb)
 where nome = 'Oliveira SJ';

select 'Atualização v56 (dados da Oliveira SJ) concluída' as resultado;
