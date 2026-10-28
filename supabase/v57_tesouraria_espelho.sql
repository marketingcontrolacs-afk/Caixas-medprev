-- =====================================================================
-- v57 · Tesouraria do cliente espelhada na Gestão financeira + suprimento automático do caixa
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v44, v45 e v43.
-- Pedido da Carol (28/10/2026):
-- 1. O cliente continua lançando na Tesouraria (Financeiro). Cada lançamento ganha uma cópia (espelho)
--    na conta "Tesouraria" da empresa na Gestão financeira, onde o escritório corrige, põe a categoria
--    e marca como revisado. O lançamento do cliente não muda.
-- 2. Se o cliente alterar ou excluir um lançamento que o escritório já revisou, o espelho fica com um
--    alerta (tes_alteracao) até o escritório aplicar a alteração ou manter a versão dele.
-- 3. Ajuste que vale para os iguais: a regra (fin_tes_regras) guarda categoria, fornecedor e descrição
--    para o mesmo tipo e a mesma descrição do cliente, e já preenche os lançamentos que chegarem depois.
-- 4. O dinheiro contado em cada fechamento de caixa entra sozinho na tesouraria do cliente como
--    Suprimento ("Dinheiro do caixa"), e acompanha as correções do caixa.
-- Todo o histórico da tesouraria (ex.: Palmas) é espelhado ao rodar.

alter table public.fin_contas     add column if not exists espelho_tes boolean not null default false;
create unique index if not exists fin_contas_espelho_tes on public.fin_contas (cliente_id) where espelho_tes;

alter table public.fin_movimentos add column if not exists tes_id        uuid;      -- lançamento da tesouraria do cliente
alter table public.fin_movimentos add column if not exists tes_chave     text;      -- descrição do cliente normalizada
alter table public.fin_movimentos add column if not exists tes_original  jsonb;     -- como o cliente lançou
alter table public.fin_movimentos add column if not exists tes_alteracao jsonb;     -- alteração do cliente depois da revisão
alter table public.fin_movimentos add column if not exists revisado      boolean not null default true;
alter table public.fin_movimentos add column if not exists por_regra     boolean not null default false;
create index if not exists fin_mov_tes on public.fin_movimentos (tes_id) where tes_id is not null;
create index if not exists fin_mov_tes_alt on public.fin_movimentos (cliente_id) where tes_alteracao is not null;

alter table public.tesouraria add column if not exists fechamento_id uuid references public.fechamentos on delete cascade;
create unique index if not exists tesouraria_fechamento on public.tesouraria (fechamento_id) where fechamento_id is not null;

create table if not exists public.fin_tes_regras (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes on delete cascade,
  tipo        text not null,          -- Despesa | Suprimento | Depósito bancário (tipo do cliente)
  chave       text not null,          -- descrição do cliente normalizada
  categoria   text,
  pessoa_nome text,
  descricao   text,
  criado_por  uuid references auth.users default auth.uid(),
  criado_em   timestamptz not null default now(),
  unique (cliente_id, tipo, chave)
);
alter table public.fin_tes_regras enable row level security;
drop policy if exists esc_tudo on public.fin_tes_regras;
create policy esc_tudo on public.fin_tes_regras for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on public.fin_tes_regras to authenticated;

-- "Frutas da semana 12/10" e "FRUTAS da Semana" viram a mesma chave
create or replace function public.tes_chave(t text) returns text
language sql immutable as
$$ select trim(regexp_replace(translate(lower(coalesce(t,'')),'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn'),'[^a-z]+',' ','g')) $$;

-- conta Tesouraria da empresa na Gestão financeira (adota a única conta "Caixa / tesouraria" que já existir)
create or replace function public.tes_conta(cli uuid) returns uuid
language plpgsql security definer set search_path = public as
$$ declare v uuid; begin
  select id into v from fin_contas where cliente_id = cli and espelho_tes;
  if v is not null then return v; end if;
  if (select count(*) from fin_contas where cliente_id = cli and tipo = 'Caixa / tesouraria') = 1 then
    update fin_contas set espelho_tes = true where cliente_id = cli and tipo = 'Caixa / tesouraria' returning id into v;
    return v;
  end if;
  insert into fin_contas (cliente_id, nome, tipo, conta_bc, saldo_inicial, espelho_tes)
  select cli, 'Tesouraria', 'Caixa / tesouraria', c.conta_tesouraria_bc, 0, true from clientes c where c.id = cli
  returning id into v;
  return v;
end $$;

create or replace function public.tes_original(t public.tesouraria) returns jsonb
language sql immutable as
$$ select jsonb_build_object('data',t.data,'tipo',t.tipo,'descricao',t.descricao,'documento',t.documento,
                            'valor',t.valor,'conta_destino',t.conta_destino,'categoria',t.categoria) $$;

-- cria o espelho de um lançamento (depósito com banco cadastrado = transferência para o banco)
create or replace function public.tes_espelho_gerar(t public.tesouraria) returns void
language plpgsql security definer set search_path = public as
$$ declare conta uuid := tes_conta(t.cliente_id); banco uuid; tf uuid; rg fin_tes_regras; k text := tes_chave(t.descricao);
begin
  select * into rg from fin_tes_regras where cliente_id = t.cliente_id and tipo = t.tipo and chave = k;
  if t.tipo = 'Depósito bancário' and t.conta_destino is not null then
    select id into banco from fin_contas where cliente_id = t.cliente_id and not espelho_tes and ativo
       and (conta_bc = t.conta_destino or nome = t.conta_destino) order by criado_em limit 1;
    if banco is not null then tf := gen_random_uuid(); end if;
  end if;
  insert into fin_movimentos (cliente_id, conta_id, data, tipo, valor, transf_id, descricao, pessoa_nome, documento, categoria,
                              tes_id, tes_chave, tes_original, revisado, por_regra, criado_por)
  values (t.cliente_id, conta, t.data, case when t.tipo = 'Suprimento' then 'entrada' else 'saida' end, t.valor, tf,
          coalesce(rg.descricao, t.descricao), rg.pessoa_nome, t.documento,
          case when t.tipo = 'Despesa' then coalesce(rg.categoria, t.categoria) else rg.categoria end,
          t.id, k, tes_original(t), rg.id is not null, rg.id is not null, t.enviado_por);
  if banco is not null then
    insert into fin_movimentos (cliente_id, conta_id, data, tipo, valor, transf_id, descricao, documento,
                                tes_id, tes_chave, tes_original, revisado, criado_por)
    values (t.cliente_id, banco, t.data, 'entrada', t.valor, tf, coalesce(rg.descricao, t.descricao), t.documento,
            t.id, k, tes_original(t), true, t.enviado_por);
  end if;
end $$;

-- o espelho acompanha o cliente enquanto o escritório não revisou; depois disso, só avisa
create or replace function public.tes_espelho_trg() returns trigger
language plpgsql security definer set search_path = public as
$$ declare rev boolean;
begin
  if tg_op = 'INSERT' then perform tes_espelho_gerar(new); return new; end if;
  select bool_or(revisado and conta_id = (select id from fin_contas where cliente_id = coalesce(new.cliente_id, old.cliente_id) and espelho_tes))
    into rev from fin_movimentos where tes_id = old.id;
  if tg_op = 'DELETE' then
    if rev then update fin_movimentos set tes_alteracao = jsonb_build_object('acao','excluido','antes',tes_original(old),'em',now()) where tes_id = old.id;
    else delete from fin_movimentos where tes_id = old.id; end if;
    return old;
  end if;
  if tes_original(old) = tes_original(new) and old.cliente_id = new.cliente_id then return new; end if;
  if rev then
    if (tes_original(old) - 'categoria') <> (tes_original(new) - 'categoria') or old.cliente_id <> new.cliente_id then
      update fin_movimentos set tes_alteracao = jsonb_build_object('acao','alterado','antes',tes_original(old),'depois',tes_original(new),'em',now())
       where tes_id = new.id;
    end if;
  else
    delete from fin_movimentos where tes_id = new.id;
    perform tes_espelho_gerar(new);
  end if;
  return new;
end $$;
drop trigger if exists tes_espelho on public.tesouraria;
create trigger tes_espelho after insert or update or delete on public.tesouraria for each row execute function public.tes_espelho_trg();

-- escritório: aplicar a alteração do cliente (refaz o espelho com os dados novos, para revisar de novo)
create or replace function public.tes_espelho_aplicar(p_tes uuid) returns void
language plpgsql security definer set search_path = public as
$$ declare t tesouraria; begin
  if not eh_escritorio() then raise exception 'Só o escritório'; end if;
  delete from fin_movimentos where tes_id = p_tes;
  select * into t from tesouraria where id = p_tes;
  if found then perform tes_espelho_gerar(t); end if;
end $$;
grant execute on function public.tes_espelho_aplicar(uuid) to authenticated;

-- dinheiro contado no fechamento do caixa entra sozinho na tesouraria do cliente
create or replace function public.caixa_para_tesouraria() returns trigger
language plpgsql security definer set search_path = public as
$$ declare v numeric := round(coalesce(new.din_cont,0),2);
           d text := 'Dinheiro do caixa' || case when coalesce(new.caixa,1) > 1 then ' ' || new.caixa else '' end;
begin
  if v <= 0 then delete from tesouraria where fechamento_id = new.id; return new; end if;
  -- importação de histórico pelo SQL Editor (sem usuário) não gera suprimento: a planilha da tesouraria já traz
  if new.enviado_por is null and auth.uid() is null then return new; end if;
  if exists (select 1 from tesouraria where fechamento_id = new.id) then
    update tesouraria set data = new.data, valor = v, descricao = d
     where fechamento_id = new.id and (data, valor, descricao) is distinct from (new.data, v, d);
  -- dias antigos em que o suprimento já foi lançado à mão ficam como estão
  elsif not exists (select 1 from tesouraria where cliente_id = new.cliente_id and data = new.data and tipo = 'Suprimento' and fechamento_id is null) then
    insert into tesouraria (cliente_id, data, tipo, descricao, valor, obs, enviado_por, fechamento_id)
    values (new.cliente_id, new.data, 'Suprimento', d, v, 'Lançado automaticamente pelo fechamento do caixa', new.enviado_por, new.id);
  end if;
  return new;
end $$;
drop trigger if exists caixa_tesouraria on public.fechamentos;
create trigger caixa_tesouraria after insert or update of din_cont, data on public.fechamentos
  for each row execute function public.caixa_para_tesouraria();

-- espelha todo o histórico que ainda não tem espelho
do $$ declare t tesouraria; begin
  for t in select * from tesouraria x where not exists (select 1 from fin_movimentos m where m.tes_id = x.id) order by data loop
    perform tes_espelho_gerar(t);
  end loop;
end $$;

notify pgrst, 'reload schema';

select c.nome as empresa, count(m.*) as lancamentos_espelhados
  from fin_movimentos m join fin_contas f on f.id = m.conta_id and f.espelho_tes join clientes c on c.id = m.cliente_id
 group by 1 order by 1;
