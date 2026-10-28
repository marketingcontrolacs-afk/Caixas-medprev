-- =====================================================================
-- v59 · Depósito da tesouraria no banco sem lançamento duplicado
-- =====================================================================
-- Rode no SQL Editor do Supabase DEPOIS da v57. Pode rodar mais de uma vez.
-- Pedido da Carol (28/10/2026): ao cadastrar as contas bancárias, a transferência da tesouraria para o banco
-- não pode duplicar o que já está lançado no banco.
-- 1. O depósito da tesouraria procura no banco uma entrada de mesmo valor até 3 dias de diferença que ainda não está
--    ligada a nada (do histórico do BC, do extrato OFX ou lançada à mão) e se liga a ela. Só cria a entrada no banco
--    quando não acha, e só se o cliente disse em qual banco depositou.
-- 2. A entrada criada pelo depósito é provisória: quando a mesma entrada chega depois pelo histórico, pelo extrato ou
--    à mão, a provisória sai e fica a do banco.
-- 3. Lançar a transferência à mão (ou por regra do extrato) com a tesouraria reaproveita o espelho do depósito em vez
--    de criar outra saída na tesouraria.
-- 4. Ao cadastrar ou alterar uma conta bancária, os depósitos da empresa são ligados de novo.

-- entrada provisória criada pelo depósito: tes_id preenchido numa conta que não é a da tesouraria
-- (não conta como lançamento feito no sistema, para os arquivos do histórico não pararem)
update public.fin_movimentos m set criado_por = null
  from public.fin_contas k where k.id = m.conta_id and not k.espelho_tes and m.tes_id is not null and m.criado_por is not null;

create or replace function public.fin_eh_banco(c uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from fin_contas where id = c and not espelho_tes and tipo <> 'Cartão de crédito') $$;

-- outra perna da transferência (em outra conta)
create or replace function public.fin_outra_perna(m public.fin_movimentos) returns public.fin_movimentos
language sql stable security definer set search_path = public as
$$ select x from fin_movimentos x where m.transf_id is not null and x.transf_id = m.transf_id and x.id <> m.id and x.conta_id <> m.conta_id
   order by (x.tes_id is null) desc limit 1 $$;

-- tira a ligação: a entrada provisória sai; a do banco fica como lançamento comum
create or replace function public.tes_desligar(p_mov uuid) returns void
language plpgsql security definer set search_path = public as
$$ declare m fin_movimentos; begin
  select * into m from fin_movimentos where id = p_mov;
  if m.transf_id is null then return; end if;
  delete from fin_movimentos where transf_id = m.transf_id and id <> m.id and conta_id <> m.conta_id and tes_id is not null;
  update fin_movimentos set transf_id = null where transf_id = m.transf_id and id <> m.id and conta_id <> m.conta_id;
  update fin_movimentos set transf_id = null where id = m.id;
end $$;

-- liga o espelho a um lançamento do banco: o que já existir; senão cria a entrada provisória (só com p_criar e conta)
create or replace function public.tes_ligar(p_mov uuid, p_conta uuid, p_criar boolean) returns uuid
language plpgsql security definer set search_path = public as
$$ declare m fin_movimentos; p fin_movimentos; c fin_movimentos; tf uuid; op text;
begin
  select * into m from fin_movimentos where id = p_mov;
  if not found then return null; end if;
  op := case when m.tipo = 'saida' then 'entrada' else 'saida' end;
  p := fin_outra_perna(m);
  if p.id is not null then
    if p_conta is null or p.conta_id = p_conta then
      if p.tes_id is not null and (p.data, p.valor, p.descricao) is distinct from (m.data, m.valor, m.descricao) then
        update fin_movimentos set data = m.data, valor = m.valor, descricao = m.descricao where id = p.id;
      end if;
      return m.transf_id;
    end if;
    perform tes_desligar(m.id); m.transf_id := null;
  end if;
  -- lançamento do banco ainda solto: mesmo valor, até 3 dias, sem conta a pagar/receber e sem outra perna
  select x.* into c from fin_movimentos x join fin_contas k on k.id = x.conta_id
   where not k.espelho_tes and k.tipo <> 'Cartão de crédito' and k.ativo
     and (k.id = p_conta or (p_conta is null and x.cliente_id = m.cliente_id))
     and x.tipo = op and x.valor = m.valor and abs(x.data - m.data) <= 3 and x.titulo_id is null and x.tes_id is null
     and (case when x.transf_id is null
               then coalesce(x.descricao,'') ~* 'dep|dinheiro|esp[eé]cie|tesour|caixa|saque' or x.categoria is null
               else not exists (select 1 from fin_movimentos y where y.transf_id = x.transf_id and y.id <> x.id) end)
   order by (x.transf_id is not null) desc, abs(x.data - m.data), x.data, x.id limit 1;
  if c.id is not null then
    tf := coalesce(m.transf_id, c.transf_id, gen_random_uuid());
    update fin_movimentos set transf_id = tf, categoria = null where id in (c.id, m.id);
    return tf;
  end if;
  if p_criar and p_conta is not null then
    tf := coalesce(m.transf_id, gen_random_uuid());
    insert into fin_movimentos (cliente_id, conta_id, data, tipo, valor, transf_id, descricao, documento, tes_id, tes_chave, tes_original, revisado)
    select k.cliente_id, k.id, m.data, op, m.valor, tf, m.descricao, m.documento, m.tes_id, m.tes_chave, m.tes_original, true
      from fin_contas k where k.id = p_conta;
    update fin_movimentos set transf_id = tf, categoria = null where id = m.id;
    return tf;
  end if;
  return m.transf_id;
end $$;

-- escritório, na tela da tesouraria: transferência para a conta escolhida (ou nenhuma, para desfazer)
create or replace function public.tes_transferir(p_mov uuid, p_conta uuid) returns uuid
language plpgsql security definer set search_path = public as
$$ begin
  if not eh_escritorio() then raise exception 'Só o escritório'; end if;
  if p_conta is null then perform tes_desligar(p_mov); return null; end if;
  return tes_ligar(p_mov, p_conta, true);
end $$;
grant execute on function public.tes_transferir(uuid, uuid) to authenticated;

-- banco do depósito pelo que o cliente escreveu
create or replace function public.tes_banco(cli uuid, destino text) returns uuid
language sql stable security definer set search_path = public as
$$ select id from fin_contas where cliente_id = cli and not espelho_tes and tipo <> 'Cartão de crédito' and ativo and destino is not null
      and (conta_bc = destino or nome = destino) order by criado_em limit 1 $$;

-- espelho de um lançamento do cliente (o depósito se liga ao banco sem duplicar)
create or replace function public.tes_espelho_gerar(t public.tesouraria) returns void
language plpgsql security definer set search_path = public as
$$ declare conta uuid := tes_conta(t.cliente_id); banco uuid; rg fin_tes_regras; k text := tes_chave(t.descricao); novo uuid;
begin
  select * into rg from fin_tes_regras where cliente_id = t.cliente_id and tipo = t.tipo and chave = k;
  insert into fin_movimentos (cliente_id, conta_id, data, tipo, valor, descricao, pessoa_nome, documento, categoria,
                              tes_id, tes_chave, tes_original, revisado, por_regra, criado_por)
  values (t.cliente_id, conta, t.data, case when t.tipo = 'Suprimento' then 'entrada' else 'saida' end, t.valor,
          coalesce(rg.descricao, t.descricao), rg.pessoa_nome, t.documento,
          case when t.tipo = 'Despesa' then coalesce(rg.categoria, t.categoria) else rg.categoria end,
          t.id, k, tes_original(t), rg.id is not null, rg.id is not null, t.enviado_por)
  returning id into novo;
  if t.tipo = 'Depósito bancário' then
    banco := tes_banco(t.cliente_id, t.conta_destino);
    perform tes_ligar(novo, banco, true);
  end if;
end $$;

-- apagar o espelho: a entrada provisória vai junto; a do banco fica solta
create or replace function public.tes_espelho_apagar(p_tes uuid) returns void
language plpgsql security definer set search_path = public as
$$ begin
  update fin_movimentos x set transf_id = null
   where x.tes_id is null and x.transf_id in (select transf_id from fin_movimentos where tes_id = p_tes and transf_id is not null);
  delete from fin_movimentos where tes_id = p_tes;
end $$;

create or replace function public.tes_espelho_trg() returns trigger
language plpgsql security definer set search_path = public as
$$ declare rev boolean;
begin
  if tg_op = 'INSERT' then perform tes_espelho_gerar(new); return new; end if;
  select bool_or(revisado and conta_id = (select id from fin_contas where cliente_id = coalesce(new.cliente_id, old.cliente_id) and espelho_tes))
    into rev from fin_movimentos where tes_id = old.id;
  if tg_op = 'DELETE' then
    if rev then update fin_movimentos set tes_alteracao = jsonb_build_object('acao','excluido','antes',tes_original(old),'em',now()) where tes_id = old.id;
    else perform tes_espelho_apagar(old.id); end if;
    return old;
  end if;
  if tes_original(old) = tes_original(new) and old.cliente_id = new.cliente_id then return new; end if;
  if rev then
    if (tes_original(old) - 'categoria') <> (tes_original(new) - 'categoria') or old.cliente_id <> new.cliente_id then
      update fin_movimentos set tes_alteracao = jsonb_build_object('acao','alterado','antes',tes_original(old),'depois',tes_original(new),'em',now())
       where tes_id = new.id;
    end if;
  else
    perform tes_espelho_apagar(new.id);
    perform tes_espelho_gerar(new);
  end if;
  return new;
end $$;

create or replace function public.tes_espelho_aplicar(p_tes uuid) returns void
language plpgsql security definer set search_path = public as
$$ declare t tesouraria; begin
  if not eh_escritorio() then raise exception 'Só o escritório'; end if;
  perform tes_espelho_apagar(p_tes);
  select * into t from tesouraria where id = p_tes;
  if found then perform tes_espelho_gerar(t); end if;
end $$;

-- antes de gravar um lançamento: não duplica o que a tesouraria já lançou
create or replace function public.fin_mov_sem_duplicar() returns trigger
language plpgsql security definer set search_path = public as
$$ declare l fin_movimentos; esp boolean;
begin
  if current_setting('fin.sem_dup', true) = 'off' then return new; end if;
  if new.tes_id is not null or new.titulo_id is not null or exists (select 1 from fin_movimentos where id = new.id) then return new; end if;
  select espelho_tes into esp from fin_contas where id = new.conta_id;
  if esp then
    -- outra saída/entrada na tesouraria para uma transferência: usa o espelho do cliente
    if new.transf_id is null then return new; end if;
    if exists (select 1 from fin_movimentos where conta_id = new.conta_id and transf_id = new.transf_id) then return null; end if;
    select x.* into l from fin_movimentos x
     where x.conta_id = new.conta_id and x.tes_id is not null and x.tipo = new.tipo and x.valor = new.valor and abs(x.data - new.data) <= 3
       and not exists (select 1 from fin_movimentos y where y.transf_id = x.transf_id and y.id <> x.id and y.tes_id is null)
     order by abs(x.data - new.data), x.data, x.id limit 1;
    if l.id is null then return new; end if;
    if l.transf_id is not null then delete from fin_movimentos where transf_id = l.transf_id and id <> l.id and tes_id is not null; end if;
    update fin_movimentos set transf_id = new.transf_id, categoria = null where id = l.id;
    return null;
  end if;
  -- lançamento do banco que a tesouraria já lançou como entrada provisória: fica o do banco
  if new.transf_id is null and coalesce(new.descricao,'') !~* 'dep|dinheiro|esp[eé]cie|tesour|caixa|saque' then return new; end if;
  select x.* into l from fin_movimentos x
   where x.conta_id = new.conta_id and x.tes_id is not null and x.ofx_id is null and x.tipo = new.tipo and x.valor = new.valor
     and abs(x.data - new.data) <= 3
   order by abs(x.data - new.data), x.data, x.id limit 1;
  if l.id is null then
    -- o banco chegou depois (histórico, extrato): liga ao depósito da tesouraria que ainda está sem banco
    if not fin_eh_banco(new.conta_id) or exists (select 1 from fin_movimentos where transf_id = new.transf_id) then return new; end if;
    select x.* into l from fin_movimentos x join fin_contas k on k.id = x.conta_id and k.espelho_tes
     where x.cliente_id = new.cliente_id and x.tes_id is not null and x.valor = new.valor and abs(x.data - new.data) <= 3
       and x.tipo = case when new.tipo = 'entrada' then 'saida' else 'entrada' end
       and (x.tes_original->>'tipo' = 'Depósito bancário' or x.transf_id is not null)
       and not exists (select 1 from fin_movimentos y where y.transf_id = x.transf_id and y.id <> x.id)
     order by abs(x.data - new.data), x.data, x.id limit 1;
    if l.id is null then return new; end if;
    if new.transf_id is null then new.transf_id := coalesce(l.transf_id, gen_random_uuid()); end if;
    new.categoria := null;
    update fin_movimentos set transf_id = new.transf_id, categoria = null where id = l.id;
    return new;
  end if;
  if new.transf_id is null then new.transf_id := l.transf_id;
  elsif not exists (select 1 from fin_movimentos where transf_id = new.transf_id) then
    update fin_movimentos set transf_id = new.transf_id where transf_id = l.transf_id and id <> l.id;
  end if;
  new.categoria := null;
  delete from fin_movimentos where id = l.id;
  return new;
end $$;
drop trigger if exists fin_mov_sem_duplicar on public.fin_movimentos;
create trigger fin_mov_sem_duplicar before insert on public.fin_movimentos
  for each row execute function public.fin_mov_sem_duplicar();

-- liga os depósitos da empresa aos bancos (roda ao cadastrar ou alterar uma conta bancária)
create or replace function public.tes_ligar_banco(cli uuid) returns int
language plpgsql security definer set search_path = public as
$$ declare r record; c fin_movimentos; p fin_movimentos; n int := 0; antes int; esp uuid;
begin
  select id into esp from fin_contas where cliente_id = cli and espelho_tes;
  if esp is null then return 0; end if;
  select count(*) into antes from fin_movimentos m where m.conta_id = esp and m.tes_id is not null and (fin_outra_perna(m)).id is not null;
  -- entrada provisória que já tem o lançamento do banco: fica o do banco
  for r in select x.* from fin_movimentos x join fin_contas k on k.id = x.conta_id
            where x.cliente_id = cli and not k.espelho_tes and x.tes_id is not null and x.ofx_id is null order by x.data loop
    select y.* into c from fin_movimentos y
     where y.conta_id = r.conta_id and y.tes_id is null and y.titulo_id is null and y.tipo = r.tipo and y.valor = r.valor
       and abs(y.data - r.data) <= 3
       and (case when y.transf_id is null then coalesce(y.descricao,'') ~* 'dep|dinheiro|esp[eé]cie|tesour|caixa|saque' or y.categoria is null
                 else not exists (select 1 from fin_movimentos z where z.transf_id = y.transf_id and z.id <> y.id) end)
     order by (y.transf_id is not null) desc, abs(y.data - r.data), y.data, y.id limit 1;
    if c.id is not null then
      update fin_movimentos set transf_id = r.transf_id, categoria = null where id = c.id;
      delete from fin_movimentos where id = r.id;
      n := n + 1;
    end if;
  end loop;
  -- depósitos (e transferências marcadas pelo BC) ainda sem o banco
  for r in select m.id, m.tes_original->>'conta_destino' destino from fin_movimentos m
            where m.conta_id = esp and m.tes_id is not null
              and (m.tes_original->>'tipo' = 'Depósito bancário' or m.transf_id is not null)
              and fin_outra_perna(m) is null order by m.data, m.id loop
    perform tes_ligar(r.id, tes_banco(cli, r.destino), true);
  end loop;
  -- vários depósitos do mesmo dia que o banco recebeu numa entrada só: a entrada do banco é dividida igual à tesouraria
  perform set_config('fin.sem_dup', 'off', true);
  for r in select m.data, array_agg(m.id order by m.valor desc, m.id) ids, sum(m.valor) tot from fin_movimentos m
            where m.conta_id = esp and m.tes_id is not null and m.tipo = 'saida' and m.tes_original->>'tipo' = 'Depósito bancário'
              and fin_outra_perna(m) is null group by m.data having count(*) > 1 order by m.data loop
    select y.* into c from fin_movimentos y join fin_contas k on k.id = y.conta_id
     where y.cliente_id = cli and not k.espelho_tes and k.tipo <> 'Cartão de crédito' and y.tipo = 'entrada' and y.valor = r.tot
       and abs(y.data - r.data) <= 3 and y.tes_id is null and y.titulo_id is null
       and (case when y.transf_id is null then coalesce(y.descricao,'') ~* 'dep|dinheiro|esp[eé]cie|tesour|caixa' or y.categoria is null
                 else not exists (select 1 from fin_movimentos z where z.transf_id = y.transf_id and z.id <> y.id) end)
     order by (y.transf_id is not null) desc, abs(y.data - r.data), y.id limit 1;
    if c.id is null then continue; end if;
    for i in 1 .. cardinality(r.ids) loop
      select * into p from fin_movimentos where id = r.ids[i];
      p.transf_id := coalesce(p.transf_id, gen_random_uuid());
      update fin_movimentos set transf_id = p.transf_id, categoria = null where id = p.id;
      if i = 1 then
        update fin_movimentos set valor = p.valor, transf_id = p.transf_id, categoria = null where id = c.id;
      else
        insert into fin_movimentos (cliente_id, conta_id, data, tipo, valor, transf_id, descricao, pessoa_nome, documento, forma, conciliado, criado_por)
        values (c.cliente_id, c.conta_id, c.data, c.tipo, p.valor, p.transf_id, c.descricao, c.pessoa_nome, c.documento, c.forma, c.conciliado, c.criado_por);
      end if;
    end loop;
  end loop;
  perform set_config('fin.sem_dup', '', true);
  select count(*) - antes + n into n from fin_movimentos m where m.conta_id = esp and m.tes_id is not null and (fin_outra_perna(m)).id is not null;
  return n;
end $$;

create or replace function public.fin_contas_ligar_tes() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if not new.espelho_tes then perform tes_ligar_banco(new.cliente_id); end if;
  return new;
end $$;
drop trigger if exists fin_contas_ligar_tes on public.fin_contas;
create trigger fin_contas_ligar_tes after insert or update of nome, conta_bc, tipo, ativo on public.fin_contas
  for each row execute function public.fin_contas_ligar_tes();

create temp table if not exists tes_lig_res(empresa text, depositos_ligados int);
truncate tes_lig_res;
insert into tes_lig_res select c.nome, tes_ligar_banco(c.id) from clientes c where exists (select 1 from fin_contas k where k.cliente_id = c.id and k.espelho_tes);

notify pgrst, 'reload schema';

select * from tes_lig_res order by 1;
