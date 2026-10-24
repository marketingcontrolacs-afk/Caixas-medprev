-- v13: empresas só de RH (Clínica Viva Simon). Pode rodar mais de uma vez.
insert into public.clientes(nome, bpo_financeiro, bpo_rh) values
  ('Clinica Viva Simon Matriz', false, true),
  ('Clinica Simon Filial',      false, true)
on conflict (nome) do update set bpo_financeiro = false, bpo_rh = true;

select nome, bpo_financeiro, bpo_rh, ativo from public.clientes where nome like 'Clinica%';
