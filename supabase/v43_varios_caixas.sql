-- =====================================================================
-- v43 · Mais de um caixa por dia na mesma empresa
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026): algumas empresas têm mais de um caixa por dia. Cada caixa tem o
-- próprio fechamento (Caixa 1, Caixa 2...). Em Configurações › Cadastro, a coluna "Caixas por dia"
-- diz quantos caixas a empresa tem (1 = como era antes). Os lançamentos que já existem viram o Caixa 1.

alter table public.clientes    add column if not exists caixas smallint not null default 1;
alter table public.fechamentos add column if not exists caixa  smallint not null default 1;

do $$ begin
  alter table public.clientes add constraint clientes_caixas_chk check (caixas between 1 and 9);
exception when duplicate_object then null; end $$;

-- antes: um fechamento por empresa e dia; agora: um por empresa, dia e caixa
do $$ declare r record; begin
  for r in select conname from pg_constraint
           where conrelid = 'public.fechamentos'::regclass and contype = 'u'
             and pg_get_constraintdef(oid) = 'UNIQUE (cliente_id, data)'
  loop execute format('alter table public.fechamentos drop constraint %I', r.conname); end loop;
end $$;
do $$ begin
  alter table public.fechamentos add constraint fechamentos_cliente_data_caixa_key unique (cliente_id, data, caixa);
exception when duplicate_table or duplicate_object then null; end $$;

notify pgrst, 'reload schema';
