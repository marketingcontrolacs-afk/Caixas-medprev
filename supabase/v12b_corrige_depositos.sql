-- Portal do Cliente (Controlacs) - correção dos depósitos do histórico (24/10/2026)
-- Rodar depois do v12. Pode rodar mais de uma vez.
-- Depósitos que estavam escritos de outro jeito ("depoisito", "Dep Inter", "Sangria - Transf Sicredi"...)
-- passam para o tipo Depósito bancário com a escrita padronizada. O texto antigo fica na observação.
-- Transferências para outras tesourarias (Pato Branco, Matriz...) e os "Maria - Depósito" NÃO são mexidos.

with alvo(texto, novo) as (values
  ('depoisito sicredi','Depósito Sicredi'),
  ('sangria - transf sicredi','Depósito Sicredi'),
  ('sangria transf sicredi','Depósito Sicredi'),
  ('sangria - transferencia sicredi','Depósito Sicredi'),
  ('sangria nov - transf sicredi','Depósito Sicredi'),
  ('sangria dez - transf sicredi','Depósito Sicredi'),
  ('sangria (transf sicredi)','Depósito Sicredi'),
  ('retirada - transferencia sicredi','Depósito Sicredi'),
  ('dep inter','Depósito Inter'),
  ('retirada - transferencia inter','Depósito Inter'),
  ('transf inter','Depósito Inter'),
  -- já reconhecidos como depósito, só a escrita
  ('deposito sicredi','Depósito Sicredi'),
  ('depósito sicred','Depósito Sicredi'),
  ('depósito/sicredi','Depósito Sicredi'),
  ('deposito conta sicredi','Depósito Sicredi'),
  ('deposito no banco','Depósito Banco')
)
update public.tesouraria t
set tipo = 'Depósito bancário',
    descricao = a.novo,
    obs = concat_ws(' | ', nullif(t.obs,''), 'Texto original: ' || t.descricao)
from alvo a
where t.tipo in ('Despesa','Depósito bancário')
  and regexp_replace(lower(trim(t.descricao)),'\s+',' ','g') = a.texto
  and t.descricao is distinct from a.novo;

select 'Correção dos depósitos concluída' as resultado,
  (select count(*) from public.tesouraria where tipo = 'Depósito bancário') as depositos_na_tesouraria;
