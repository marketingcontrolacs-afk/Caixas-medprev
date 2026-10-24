-- Portal do Cliente (Controlacs) - v18: início do trabalho antes do registro (24/10/2026)
-- Pode rodar mais de uma vez. Quem começou a trabalhar antes da admissão recebe esses dias como
-- "Dif de salário" na folha do mês em que começou (ex.: começou 07/10, admitido 09/10 = "2 dias").
alter table public.funcionarios add column if not exists inicio_trabalho date;

-- Preenche pelo que está escrito na observação dos prazos ("Iniciou dia 07/10/2026")
update public.funcionarios
   set inicio_trabalho = to_date(substring(prazos_obs from '(\d{2}/\d{2}/\d{4})'), 'DD/MM/YYYY')
 where inicio_trabalho is null and prazos_obs ~* 'inici' and prazos_obs ~ '\d{2}/\d{2}/\d{4}';

notify pgrst, 'reload schema';

select f.nome, f.inicio_trabalho, f.admissao, f.admissao - f.inicio_trabalho as dias_sem_registro
  from public.funcionarios f
 where f.inicio_trabalho is not null order by f.inicio_trabalho;
