-- =====================================================================
-- v29 · Oliveira: assiduidade de R$ 100 para todos (inclusive gestores)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Regra (Carol, 25/10): nas três Oliveiras todos ganham R$ 100 de assiduidade, inclusive os gestores (que não batem ponto).
-- Só ganha quem trabalhou todo o período do ponto: qualquer falta (dia ou horas) ou atestado zera. Para gestor que faltar,
-- o escritório edita a célula na folha. Quem já tem valor no cadastro fica como está. A Eliete (Biguaçu, sem registro) fica de fora.

update public.funcionarios f
   set folha_fixos = coalesce(f.folha_fixos,'{}'::jsonb) || '{"assiduidade":100}'::jsonb
  from public.clientes c
 where c.id = f.cliente_id
   and c.nome in ('Oliveira SJ','Oliveira Biguaçu','Oliveira Palhoça')
   and f.situacao <> 'Desligado'
   and f.nome !~* '^eliete'
   and coalesce(f.folha_fixos->>'assiduidade','') = '';

notify pgrst, 'reload schema';

select c.nome as empresa, f.nome as colaborador, f.situacao, f.folha_fixos->>'assiduidade' as assiduidade
  from public.funcionarios f join public.clientes c on c.id = f.cliente_id
 where c.nome in ('Oliveira SJ','Oliveira Biguaçu','Oliveira Palhoça') and f.situacao <> 'Desligado'
 order by 1, 2;
