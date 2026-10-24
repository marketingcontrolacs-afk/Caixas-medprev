-- =====================================================================
-- v25 · Faltas em horas, faltas em dias e DSR em todas as folhas
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Regra (Carol, 24/10/2026): toda empresa lança falta em horas e falta em dias, com a coluna DSR.
-- Faltou o dia inteiro: desconta o dia e DSR "Sim". Faltou algumas horas: desconta só as horas.
-- Nas Oliveira, a coluna "Faltas" (pela data) vira Faltas/ Horas, Faltas/ Dias e DSR, no mesmo lugar.
-- Empresas com folha que ainda não têm essas colunas ganham as três no fim dos descontos.

update public.clientes c
   set folha_colunas = (select array_agg(x order by o, s)
                          from unnest(c.folha_colunas) with ordinality u(col, o),
                               lateral unnest(case when col = 'faltas_data' then array['faltas_horas','faltas_dias','dsr'] else array[col] end)
                               with ordinality v(x, s))
 where 'faltas_data' = any(c.folha_colunas);

-- faltas já lançadas pela data viram falta de 1 dia com DSR
update public.folha_lancamentos set coluna = 'faltas_dias', texto = 'dsr' where coluna = 'faltas_data';

-- qualquer outra empresa com folha: garante as três colunas
update public.clientes c
   set folha_colunas = c.folha_colunas
       || (select coalesce(array_agg(x), '{}') from unnest(array['faltas_horas','faltas_dias','dsr']) x where not x = any(c.folha_colunas))
 where c.folha_colunas is not null and array_length(c.folha_colunas, 1) > 0
   and not (c.folha_colunas @> array['faltas_horas','faltas_dias','dsr']);

notify pgrst, 'reload schema';

select nome, array_to_string(folha_colunas, ', ') as colunas from public.clientes where folha_colunas is not null order by nome;
