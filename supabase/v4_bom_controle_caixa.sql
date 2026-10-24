-- Portal do Cliente (Controlacs) - atualização v4: importação do Bom Controle do caixa (24/10/2026)
-- Rodar depois do v3_rh_ferias.sql. Pode rodar mais de uma vez.
-- Regras da Carol (iguais para todas as empresas, só muda a conta):
--   entrada de dinheiro do caixa = Receita, conta Tesouraria da empresa, CPF 572.590.930-13,
--   "Usuários Diversos***", Dinheiro, Recebimento de Atendimentos, sem departamento, Pago,
--   todas as datas = data do caixa, valor bruto, demais colunas em branco.
--   Na Tesouraria só entra dinheiro: débito e crédito ficam fora da importação por enquanto.

-- Conta Tesouraria de cada empresa no Bom Controle (Configurações > Empresas)
alter table public.clientes add column if not exists conta_tesouraria_bc text;
update public.clientes set conta_tesouraria_bc = 'Tesouraria - MPA - Filial Palmas'
where nome = 'MPA Palmas' and conta_tesouraria_bc is null;

update public.mapeamento_bc set tipo = 'Receita', conta = null, cnpj = '572.590.930-13', nome = 'Usuários Diversos***',
  forma = 'Dinheiro', categoria = 'Recebimento de Atendimentos', departamento = null, status = 'Pago', etiqueta = null
where lancamento = 'Venda em dinheiro';
