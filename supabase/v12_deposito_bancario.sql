-- Portal do Cliente (Controlacs) - atualização v12: Depósito bancário na Tesouraria (24/10/2026)
-- Rodar depois do v11_fornecedores_bc.sql. Pode rodar mais de uma vez.
-- Depósito do dinheiro da tesouraria no banco: categoria sempre "Depósito Bancário", sem confirmação
-- de categoria. O escritório só confere valor, data e as contas de saída (Tesouraria) e de destino (banco).
-- Na exportação para o Bom Controle vira 2 lançamentos: saída da Tesouraria e entrada no banco.

alter table public.tesouraria drop constraint if exists tesouraria_tipo_check;
alter table public.tesouraria add constraint tesouraria_tipo_check
  check (tipo in ('Despesa','Suprimento','Depósito bancário'));
alter table public.tesouraria add column if not exists conta_destino text;   -- conta do banco no Bom Controle

-- Banco onde a empresa costuma depositar (vem preenchido no lançamento e vale para o histórico)
alter table public.clientes add column if not exists conta_deposito_bc text;

insert into public.plano_contas(categoria, tipo) values ('Depósito Bancário','Despesa')
on conflict (categoria) do nothing;

insert into public.mapeamento_bc(lancamento, tipo, categoria, status) values
 ('Depósito bancário - saída','Despesa','Depósito Bancário','Pago'),
 ('Depósito bancário - entrada','Receita','Depósito Bancário','Pago')
on conflict (lancamento) do nothing;

-- Histórico: despesas da tesouraria que são depósitos ("Deposito Sicredi", "Depósito Banco"...)
update public.tesouraria set tipo = 'Depósito bancário'
where tipo = 'Despesa' and translate(lower(descricao),'óôõ','ooo') ~ '(^|[^a-z])deposit';

select 'Atualização v12 (Depósito bancário) concluída' as resultado,
  (select count(*) from public.tesouraria where tipo = 'Depósito bancário') as depositos_na_tesouraria;
