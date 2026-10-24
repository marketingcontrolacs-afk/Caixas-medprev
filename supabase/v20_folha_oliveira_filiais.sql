-- =====================================================================
-- v20 · Folha de Biguaçu e Palhoça no mesmo modelo da Oliveira SJ
-- =====================================================================
-- Rode no SQL Editor do Supabase depois da v19. Pode rodar mais de uma vez.
-- Copia as colunas e o modelo da planilha da Oliveira SJ, trocando só o título, e põe a
-- assiduidade de R$ 100 em quem ainda não tem (como na SJ). O resto dos fixos o escritório
-- preenche em Folha › Colaboradores e valores fixos.

update public.clientes d
   set folha_colunas = s.folha_colunas,
       folha_modelo  = s.folha_modelo || jsonb_build_object('titulo', d.nome),
       bpo_rh = true
  from public.clientes s
 where s.nome = 'Oliveira SJ' and s.folha_colunas is not null
   and d.nome in ('Oliveira Biguaçu', 'Oliveira Palhoça');

update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos, '{}'::jsonb) || '{"assiduidade":100}'::jsonb
  from public.clientes c
 where c.id = f.cliente_id and c.nome in ('Oliveira Biguaçu', 'Oliveira Palhoça')
   and f.situacao <> 'Desligado' and not coalesce(f.folha_fixos, '{}'::jsonb) ? 'assiduidade';

notify pgrst, 'reload schema';

select c.nome as empresa, c.folha_modelo->>'titulo' as titulo_da_planilha,
       coalesce(array_length(c.folha_colunas, 1), 0) as colunas,
       (select count(*) from public.funcionarios f where f.cliente_id = c.id and f.situacao <> 'Desligado') as colaboradores_ativos
  from public.clientes c where c.nome like 'Oliveira%' order by 1;
