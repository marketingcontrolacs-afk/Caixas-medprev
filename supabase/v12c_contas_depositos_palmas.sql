-- Portal do Cliente (Controlacs) - contas de destino dos depósitos da MPA Palmas (24/10/2026)
-- Rodar depois do v12b. Pode rodar mais de uma vez. Nomes das contas como estão no Bom Controle.
update public.clientes set conta_deposito_bc = 'Banco Sicredi - Filial MPA Palmas'
where nome = 'MPA Palmas' and conta_deposito_bc is null;

update public.tesouraria t set conta_destino = 'Banco Sicredi - Filial MPA Palmas'
from public.clientes c
where c.id = t.cliente_id and c.nome = 'MPA Palmas'
  and t.tipo = 'Depósito bancário' and t.descricao = 'Depósito Sicredi' and t.conta_destino is null;

update public.tesouraria t set conta_destino = 'Banco Inter - Filial Palmas'
from public.clientes c
where c.id = t.cliente_id and c.nome = 'MPA Palmas'
  and t.tipo = 'Depósito bancário' and t.descricao = 'Depósito Inter' and t.conta_destino is null;

select 'Contas dos depósitos da Palmas concluídas' as resultado,
  (select count(*) from public.tesouraria t join public.clientes c on c.id = t.cliente_id
    where c.nome = 'MPA Palmas' and t.tipo = 'Depósito bancário' and t.conta_destino is not null) as com_banco,
  (select count(*) from public.tesouraria t join public.clientes c on c.id = t.cliente_id
    where c.nome = 'MPA Palmas' and t.tipo = 'Depósito bancário' and t.conta_destino is null) as usam_o_banco_padrao;
