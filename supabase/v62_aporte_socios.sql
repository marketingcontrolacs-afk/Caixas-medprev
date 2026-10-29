-- =====================================================================
-- v62 · Categoria "Aporte de sócios" (Movimentação financeira › tipo Aportes)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v52.
-- Aporte é dinheiro que os sócios colocam na empresa: entra no caixa e no fluxo de caixa,
-- mas não é receita, então fica fora da DRE. O portal trata como aporte toda entrada
-- com "aporte" no nome da categoria.

insert into public.plano_contas (categoria,codigo,grupo,tipo) values
('Aporte de sócios','1.4.01','Aportes de capital','Receita')
on conflict (categoria) do nothing;

-- empresas com plano de contas próprio também recebem a categoria
insert into public.fin_plano (cliente_id,codigo,categoria,tipo,ativo,grupo)
select c.id,'1.4.01','Aporte de sócios','Receita',true,'Aportes de capital'
from public.clientes c where c.plano_proprio
on conflict (cliente_id,categoria) do nothing;
