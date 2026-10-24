-- Portal do Cliente (Controlacs) - atualização v5: férias sempre em dia (24/10/2026)
-- Rodar depois do v3_rh_ferias.sql. Pode rodar mais de uma vez.
-- O sistema abre sozinho o novo período aquisitivo de cada colaborador quando o anterior
-- completa 1 ano, e cria o primeiro período de quem for cadastrado sem nenhum.
-- Saldo, limite, "iniciar até" e situação já são recalculados todo dia na v_ferias
-- (usam a data de hoje), então não é preciso pedir relatório à contabilidade.

-- Cria os períodos aquisitivos que faltam (de um colaborador ou de todos). Devolve quantos criou.
create or replace function public.ferias_gerar_periodos(func uuid default null) returns int
language plpgsql security definer set search_path = public as
$$ declare r record; prox date; n int := 0; k int;
begin
  for r in select f.id, f.admissao,
                  (select max(p.inicio_aquisitivo) from ferias_periodos p where p.funcionario_id = f.id) as ultimo
           from funcionarios f
           where f.situacao <> 'Desligado' and (func is null or f.id = func)
  loop
    if r.ultimo is not null then
      prox := (r.ultimo + interval '1 year')::date;
    elsif r.admissao is not null then
      -- sem nenhum período: abre o período em curso, contado da admissão
      prox := (r.admissao + make_interval(years => greatest(extract(year from age(current_date, r.admissao))::int, 0)))::date;
    else
      continue;
    end if;
    while prox <= current_date loop
      insert into ferias_periodos(funcionario_id, inicio_aquisitivo) values (r.id, prox)
      on conflict (funcionario_id, inicio_aquisitivo) do nothing;
      get diagnostics k = row_count; n := n + k;
      prox := (prox + interval '1 year')::date;
    end loop;
  end loop;
  return n;
end $$;

-- Colaborador novo (ou admissão corrigida): já entra com o período aquisitivo
create or replace function public.ferias_periodo_do_novo() returns trigger
language plpgsql security definer set search_path = public as
$$ begin perform ferias_gerar_periodos(new.id); return new; end $$;
drop trigger if exists gera_periodo on public.funcionarios;
create trigger gera_periodo after insert or update of admissao, situacao on public.funcionarios
  for each row execute function public.ferias_periodo_do_novo();

-- Rotina diária no Supabase (pg_cron). Se a extensão não estiver liberada, o Portal
-- faz a mesma atualização sempre que alguém abre a tela de Férias.
do $$ begin
  create extension if not exists pg_cron;
  execute $c$select cron.schedule('ferias-periodos', '10 3 * * *', 'select public.ferias_gerar_periodos()')$c$;
exception when others then
  raise notice 'Rotina diária não agendada (%). O Portal atualiza ao abrir Férias.', sqlerrm;
end $$;

grant execute on function public.ferias_gerar_periodos(uuid) to authenticated;

notify pgrst, 'reload schema';
select 'Atualização v5 (férias automáticas) concluída' as resultado,
       public.ferias_gerar_periodos() as periodos_criados_agora;
