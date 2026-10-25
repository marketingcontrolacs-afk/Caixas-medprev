-- =====================================================================
-- v35 · Pedido de benefícios: dias úteis + escala de sábados; VA fixo com assiduidade (Viva)
-- =====================================================================
-- Rode no SQL Editor do Supabase depois da v34. Pode rodar mais de uma vez.
-- Regra (Carol, 25/10/2026): os benefícios seguem o espelho de ponto. O pedido é para o mês seguinte:
--   dias = dias úteis do mês (seg a sex, fora feriados) + sábados que a pessoa vai trabalhar (escala) − faltas e atestados.
--   VT de todas as empresas e o VA por dia (Oliveira e BJ) usam esses dias.
--   Viva: VA fixo, que não é descontado por atestado, mais a assiduidade paga junto no VA, que a pessoa perde se faltar.
alter table public.beneficios_pedidos add column if not exists dias_uteis    int;
alter table public.beneficios_pedidos add column if not exists sab_trab      int;
alter table public.beneficios_pedidos add column if not exists sab_datas     text[];
alter table public.beneficios_pedidos add column if not exists faltas_injust numeric;   -- faltas sem atestado (tiram a assiduidade)
alter table public.beneficios_pedidos add column if not exists assid         numeric;   -- assiduidade paga junto no VA fixo
alter table public.beneficios_meses   add column if not exists dias_uteis    int;

-- escala de sábados no cadastro: 'todos', 'alt' (um sim, um não) ou 'nao'; vem dos "sábados não trabalhados" da v34
update public.funcionarios
   set folha_fixos = (folha_fixos - 'vt_sab_nao') || jsonb_build_object('sab_escala',
         case when (folha_fixos->>'vt_sab_nao')::int >= 4 then 'nao' when (folha_fixos->>'vt_sab_nao')::int >= 2 then 'alt' else 'todos' end)
 where folha_fixos ? 'vt_sab_nao' and not folha_fixos ? 'sab_escala';

-- Viva Matriz e Filial: VT com as mesmas regras e desconto de 6% de VT e R$ 1,00 de VA na folha
update public.clientes
   set folha_modelo = coalesce(folha_modelo,'{}'::jsonb) || '{"beneficios":{"desconta":true,"combustivel":false,"confirmado":true,"va_fixo":true}}'::jsonb
 where nome in ('Clinica Viva Simon Matriz','Clinica Simon Filial');

notify pgrst, 'reload schema';

select c.nome as empresa, count(*) filter (where f.folha_fixos ? 'sab_escala') as com_escala_de_sabado
  from public.clientes c join public.funcionarios f on f.cliente_id = c.id
 where c.nome like 'Oliveira%' group by 1 order by 1;
