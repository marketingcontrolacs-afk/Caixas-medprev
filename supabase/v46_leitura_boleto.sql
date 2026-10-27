-- =====================================================================
-- v46 · Leitura do boleto e da nota fiscal nos boletos enviados pelo cliente
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v45. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): ao anexar o boleto (PDF) ou colar a linha digitável, o portal lê
-- o valor e o vencimento; a chave de acesso da NF-e traz o CNPJ do emitente e o número da nota.
-- A linha digitável fica guardada para o pagamento por arquivo (CNAB), mais adiante.

alter table public.contas_pagar add column if not exists linha_digitavel text;
alter table public.contas_pagar add column if not exists nfe_chave       text;

-- o cliente não vê a lista de fornecedores do Bom Controle; esta função devolve só o nome
-- do fornecedor com aquele CNPJ/CPF, para preencher o campo Fornecedor a partir da nota
create or replace function public.fornecedor_por_documento(doc text) returns text
language sql stable security definer set search_path = public as
$$ select razao_social from public.fornecedores_bc
   where length(regexp_replace(coalesce(doc,''), '\D', '', 'g')) in (11, 14)
     and regexp_replace(coalesce(documento,''), '\D', '', 'g') = regexp_replace(doc, '\D', '', 'g')
   order by bloqueado limit 1 $$;
revoke all on function public.fornecedor_por_documento(text) from public;
grant execute on function public.fornecedor_por_documento(text) to authenticated;

select 'Atualização v46 (leitura do boleto e da nota) concluída' as resultado;
