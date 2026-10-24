-- Portal do Cliente (Controlacs) - atualização v6: Exportação Bom Controle no Escritório (24/10/2026)
-- Rodar depois do v4_bom_controle_caixa.sql. Pode rodar mais de uma vez.
-- A exportação saiu da tela do Caixa e virou um módulo do Escritório (só a equipe Controlacs vê),
-- com a origem à escolha: Caixa, Tesouraria, Banco (contas a pagar) e Cartão de crédito.
-- Cria uma linha de mapeamento para cada nova origem. Complete conta, categoria, forma etc.
-- em Configurações > Mapeamento Bom Controle, com os nomes iguais aos do Bom Controle.
--   Tesouraria - Despesa: a conta é sempre a Tesouraria da empresa (Configurações > Empresas).
--   Contas a pagar: a conta é o banco informado ao marcar a conta como paga; a do mapeamento só vale se faltar.
--   Cartão de crédito: a conta é a do mapeamento (ex.: o cartão no Bom Controle).

insert into public.mapeamento_bc(lancamento, tipo, status) values
 ('Tesouraria - Despesa','Despesa','Pago'),
 ('Contas a pagar','Despesa','Pago'),
 ('Cartão de crédito','Despesa','Pago')
on conflict (lancamento) do nothing;

select 'Atualização v6 (Exportação Bom Controle) concluída' as resultado;
