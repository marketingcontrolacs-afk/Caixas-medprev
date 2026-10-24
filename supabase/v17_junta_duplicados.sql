-- Portal do Cliente (Controlacs) - v17: junta colaboradores duplicados (24/10/2026)
-- Pode rodar mais de uma vez. Rodar os arquivos de carga mais de uma vez, em outra ordem, criou o mesmo
-- colaborador duas vezes (às vezes um com o primeiro nome e outro com o nome completo).
-- 1) passa os nomes curtos para o nome completo; 2) em cada empresa, junta quem tem o mesmo nome:
-- fica um só, com todos os dados preenchidos dos dois, e os lançamentos, ajustes, rescisões e férias
-- passam para ele; 3) apaga rescisões repetidas.

update public.funcionarios f set nome = v.novo
  from public.clientes c, (values
    ('Darllea','Darllea do Socorro'),
    ('Jussara','Jussara Garcia Rodrigues'),
    ('Kauani Ferreira','Kauani Vitoria Correa Ferreira'),
    ('Larissa','Larissa de Brito'),
    ('Pedro','Pedro Vitor'),
    ('Bruna Batista','Bruna Batista da Silva'),
    ('Elaine','Elaine Claudino dos Santos'),
    ('Cintia Roberta Amorim de S Ferreira','Cintia Roberta Amorim de Souza Ferreira')
  ) as v(antigo, novo)
 where c.id = f.cliente_id and (c.nome ilike '%simon%' or c.nome ilike '%kobrasol%') and f.nome = v.antigo;
update public.funcionarios set nome = btrim(nome) where nome <> btrim(nome);

do $$
declare g record; fica uuid; sai uuid[];
begin
  for g in select cliente_id, lower(nome) as n from public.funcionarios group by 1,2 having count(*) > 1 loop
    -- fica o que tem matrícula e mais dados preenchidos
    select id into fica from public.funcionarios
     where cliente_id = g.cliente_id and lower(nome) = g.n
     order by (matricula is not null) desc, (fim_experiencia2 is not null) desc, (nascimento is not null) desc,
              (folha_quebra_cx is not null or folha_insalubridade is not null or folha_ajuda_custo is not null) desc, id
     limit 1;
    select array_agg(id) into sai from public.funcionarios where cliente_id = g.cliente_id and lower(nome) = g.n and id <> fica;

    -- completa o que fica com os dados dos outros
    update public.funcionarios k set
      matricula = coalesce(k.matricula, o.matricula), admissao = coalesce(k.admissao, o.admissao),
      situacao = case when 'Desligado' = any(o.sits) or k.situacao = 'Desligado' then 'Desligado'
                      when 'Afastado' = any(o.sits) or k.situacao = 'Afastado' then 'Afastado' else k.situacao end,
      afastado_desde = coalesce(k.afastado_desde, o.afastado_desde), motivo_afastamento = coalesce(k.motivo_afastamento, o.motivo_afastamento),
      desligado_em = greatest(k.desligado_em, o.desligado_em), obs = coalesce(k.obs, o.obs), cargo = coalesce(k.cargo, o.cargo),
      folha_ajuda_custo = coalesce(k.folha_ajuda_custo, o.folha_ajuda_custo), folha_gratificacao = coalesce(k.folha_gratificacao, o.folha_gratificacao),
      folha_quebra_cx = coalesce(k.folha_quebra_cx, o.folha_quebra_cx), folha_insalubridade = coalesce(k.folha_insalubridade, o.folha_insalubridade),
      folha_vt = k.folha_vt or o.folha_vt, nascimento = coalesce(k.nascimento, o.nascimento),
      fim_experiencia1 = coalesce(k.fim_experiencia1, o.fim_experiencia1), fim_experiencia2 = coalesce(k.fim_experiencia2, o.fim_experiencia2),
      ultimo_dia_aviso = coalesce(k.ultimo_dia_aviso, o.ultimo_dia_aviso), prazos_obs = coalesce(k.prazos_obs, o.prazos_obs),
      va_valor = coalesce(k.va_valor, o.va_valor), vt_valor_dia = coalesce(k.vt_valor_dia, o.vt_valor_dia),
      vt_empresa = coalesce(k.vt_empresa, o.vt_empresa), telefone = coalesce(k.telefone, o.telefone)
    from (select max(matricula) matricula, min(admissao) admissao, array_agg(situacao) sits, min(afastado_desde) afastado_desde,
                 max(motivo_afastamento) motivo_afastamento, max(desligado_em) desligado_em, max(obs) obs, max(cargo) cargo,
                 max(folha_ajuda_custo) folha_ajuda_custo, max(folha_gratificacao) folha_gratificacao, max(folha_quebra_cx) folha_quebra_cx,
                 max(folha_insalubridade) folha_insalubridade, bool_or(folha_vt) folha_vt, max(nascimento) nascimento,
                 max(fim_experiencia1) fim_experiencia1, max(fim_experiencia2) fim_experiencia2, max(ultimo_dia_aviso) ultimo_dia_aviso,
                 max(prazos_obs) prazos_obs, max(va_valor) va_valor, max(vt_valor_dia) vt_valor_dia, max(vt_empresa) vt_empresa, max(telefone) telefone
            from public.funcionarios where id = any(sai)) o
    where k.id = fica;

    -- o que estava ligado aos duplicados passa para o que fica
    update public.folha_lancamentos set funcionario_id = fica where funcionario_id = any(sai);
    delete from public.folha_ajustes a where a.funcionario_id = any(sai)
       and exists (select 1 from public.folha_ajustes b where b.funcionario_id = fica and b.competencia = a.competencia and b.coluna = a.coluna);
    update public.folha_ajustes set funcionario_id = fica where funcionario_id = any(sai);
    update public.folha_rescisoes set funcionario_id = fica where funcionario_id = any(sai);
    delete from public.ferias_periodos p where p.funcionario_id = any(sai)
       and exists (select 1 from public.ferias_periodos q where q.funcionario_id = fica and q.inicio_aquisitivo = p.inicio_aquisitivo);
    update public.ferias_periodos set funcionario_id = fica where funcionario_id = any(sai);
    -- matrícula repetida impediria a gravação: tira dos que saem antes de apagar
    update public.funcionarios set matricula = null where id = any(sai);
    delete from public.funcionarios where id = any(sai);
  end loop;
end $$;

-- rescisão repetida (mesma pessoa e mesma data de demissão): fica a mais antiga
delete from public.folha_rescisoes r using public.folha_rescisoes s
 where r.funcionario_id = s.funcionario_id and r.data_demissao = s.data_demissao
   and (r.criado_em, r.id::text) > (s.criado_em, s.id::text);

notify pgrst, 'reload schema';

select c.nome as empresa, count(f.id) as colaboradores, count(distinct lower(f.nome)) as nomes_diferentes,
       (select count(*) from public.folha_rescisoes r where r.cliente_id = c.id) as rescisoes
  from public.clientes c left join public.funcionarios f on f.cliente_id = c.id
 where c.bpo_rh group by c.id, c.nome order by c.nome;
