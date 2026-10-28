-- =====================================================================
-- v58 · Clientes e fornecedores sem cadastro repetido
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v44 e da v45.
-- Pedido da Carol (28/10/2026):
-- 1. Junta os cadastros repetidos (mesmo nome, sem diferença de maiúsculas, acentos, pontuação e LTDA/ME/EPP/EIRELI/SA).
--    Fica um de cada, com os dados que faltavam completados pelos outros; as contas a pagar e a receber passam para ele.
--    O mesmo nome com CNPJs diferentes continua separado.
-- 2. "Usuários Diversos***" vira "Usuários Diversos".
-- 3. Daqui em diante o banco não deixa cadastrar o mesmo nome de novo, a não ser com outro CNPJ
--    (pessoa física nunca), nem o mesmo CNPJ/CPF duas vezes.

create or replace function public.pessoa_chave(t text) returns text
language sql immutable as
$$ select regexp_replace(trim(regexp_replace(translate(replace(lower(coalesce(t,'')),'&',' e '),'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn'),'[^a-z0-9]+',' ','g')),
                         '( (ltda|me|epp|eireli|sa|s a|mei))+$','') $$;
create or replace function public.so_digitos(t text) returns text
language sql immutable as $$ select regexp_replace(coalesce(t,''),'\D','','g') $$;

-- Usuários Diversos*** → Usuários Diversos (cadastro e lançamentos)
update public.fin_pessoas set nome = 'Usuários Diversos' where pessoa_chave(nome) = 'usuarios diversos' and nome <> 'Usuários Diversos';
update public.fin_titulos    set pessoa_nome = 'Usuários Diversos' where pessoa_chave(pessoa_nome) = 'usuarios diversos' and pessoa_nome <> 'Usuários Diversos';
update public.fin_movimentos set pessoa_nome = 'Usuários Diversos' where pessoa_chave(pessoa_nome) = 'usuarios diversos' and pessoa_nome <> 'Usuários Diversos';
do $$ begin
  update public.fin_tes_regras set pessoa_nome = 'Usuários Diversos' where pessoa_chave(pessoa_nome) = 'usuarios diversos' and pessoa_nome <> 'Usuários Diversos';
exception when undefined_table then null; end $$;

drop trigger if exists pessoa_unica on public.fin_pessoas;

create temp table if not exists pes_res(grupos int, apagados int);
truncate pes_res;
do $$ declare k text; docs text[]; d text; ids uuid[]; keep uuid; outros uuid[]; o record; ng int := 0; na int := 0;
begin
  for k in select pessoa_chave(nome) from fin_pessoas group by 1 having count(*) > 1 loop
    select coalesce(array_agg(distinct so_digitos(documento)) filter (where so_digitos(documento) <> ''), '{}') into docs
      from fin_pessoas where pessoa_chave(nome) = k;
    -- até um documento: todos juntos; mais de um: um grupo por documento e os sem documento à parte
    for d in select unnest(case when cardinality(docs) <= 1 then array['*'] else docs || array[''] end) loop
      select array_agg(id order by (fornecedor_bc is not null) desc, (so_digitos(documento) <> '') desc,
                       (select count(*) from fin_titulos t where t.pessoa_id = p.id) desc, criado_em, id)
        into ids from fin_pessoas p where pessoa_chave(nome) = k and (d = '*' or so_digitos(documento) = d);
      if coalesce(cardinality(ids),0) < 2 then continue; end if;
      keep := ids[1]; outros := ids[2:];
      select (array_agg(fantasia) filter (where fantasia is not null))[1] fantasia, (array_agg(documento) filter (where documento is not null))[1] documento,
             (array_agg(grupo) filter (where grupo is not null))[1] grupo, (array_agg(email) filter (where email is not null))[1] email,
             (array_agg(telefone) filter (where telefone is not null))[1] telefone, (array_agg(cidade) filter (where cidade is not null))[1] cidade,
             (array_agg(pix_tipo) filter (where pix_chave is not null))[1] pix_tipo, (array_agg(pix_chave) filter (where pix_chave is not null))[1] pix_chave,
             (array_agg(banco) filter (where banco is not null))[1] banco, (array_agg(agencia) filter (where agencia is not null))[1] agencia,
             (array_agg(conta) filter (where conta is not null))[1] conta, (array_agg(fornecedor_bc) filter (where fornecedor_bc is not null))[1] fornecedor_bc,
             (array_agg(cep) filter (where cep is not null))[1] cep, (array_agg(endereco) filter (where endereco is not null))[1] endereco,
             (array_agg(numero) filter (where numero is not null))[1] numero, (array_agg(complemento) filter (where complemento is not null))[1] complemento,
             (array_agg(bairro) filter (where bairro is not null))[1] bairro, (array_agg(uf) filter (where uf is not null))[1] uf,
             (array_agg(situacao_receita) filter (where situacao_receita is not null))[1] situacao_receita, (array_agg(situacao_em) filter (where situacao_em is not null))[1] situacao_em,
             string_agg(distinct obs, ' | ') obs, count(distinct papel) papeis, min(papel) papel1,
             count(distinct coalesce(cliente_id::text,'')) clis, (array_agg(cliente_id))[1] cli1, bool_or(ativo) ativo
        into o from fin_pessoas where id = any(outros);
      update fin_titulos set pessoa_id = keep where pessoa_id = any(outros);
      delete from fin_pessoas where id = any(outros);
      update fin_pessoas p set fantasia = coalesce(p.fantasia, o.fantasia), documento = coalesce(p.documento, o.documento), grupo = coalesce(p.grupo, o.grupo),
             email = coalesce(p.email, o.email), telefone = coalesce(p.telefone, o.telefone), cidade = coalesce(p.cidade, o.cidade),
             pix_tipo = case when p.pix_chave is null then o.pix_tipo else p.pix_tipo end, pix_chave = coalesce(p.pix_chave, o.pix_chave),
             banco = coalesce(p.banco, o.banco), agencia = coalesce(p.agencia, o.agencia), conta = coalesce(p.conta, o.conta),
             fornecedor_bc = coalesce(p.fornecedor_bc, o.fornecedor_bc), cep = coalesce(p.cep, o.cep), endereco = coalesce(p.endereco, o.endereco),
             numero = coalesce(p.numero, o.numero), complemento = coalesce(p.complemento, o.complemento), bairro = coalesce(p.bairro, o.bairro),
             uf = coalesce(p.uf, o.uf), situacao_receita = coalesce(p.situacao_receita, o.situacao_receita), situacao_em = coalesce(p.situacao_em, o.situacao_em),
             obs = coalesce(p.obs, o.obs), ativo = p.ativo or o.ativo,
             papel = case when o.papeis > 1 or o.papel1 is distinct from p.papel then 'ambos' else p.papel end,
             cliente_id = case when o.clis > 1 or o.cli1 is distinct from p.cliente_id then null else p.cliente_id end
       where p.id = keep;
      ng := ng + 1; na := na + cardinality(outros);
    end loop;
  end loop;
  insert into pes_res values (ng, na);
end $$;

-- O mesmo nome só com CNPJ diferente (pessoa física nunca); o mesmo CNPJ/CPF nunca
create or replace function public.pessoa_unica() returns trigger
language plpgsql as
$$ declare d text := so_digitos(new.documento); x record;
begin
  if d <> '' then
    select nome into x from fin_pessoas o where o.id <> new.id and so_digitos(o.documento) = d
       and (o.cliente_id is null or new.cliente_id is null or o.cliente_id = new.cliente_id) limit 1;
    if found then raise exception 'Já existe um cadastro com esse CNPJ/CPF: %.', x.nome; end if;
  end if;
  select nome, documento into x from fin_pessoas o where o.id <> new.id and pessoa_chave(o.nome) = pessoa_chave(new.nome)
     and (o.cliente_id is null or new.cliente_id is null or o.cliente_id = new.cliente_id)
     and not (length(d) = 14 and length(so_digitos(o.documento)) = 14 and d <> so_digitos(o.documento)) limit 1;
  if found then
    raise exception 'Já existe “%” no cadastro%. O mesmo nome só pode ser cadastrado de novo com outro CNPJ; pessoa física nunca.',
      x.nome, case when x.documento is not null then ' (' || x.documento || ')' else '' end;
  end if;
  return new;
end $$;
create trigger pessoa_unica before insert or update of nome, documento, cliente_id on public.fin_pessoas
  for each row execute function public.pessoa_unica();

notify pgrst, 'reload schema';

select grupos as nomes_repetidos_juntados, apagados as cadastros_repetidos_removidos,
       (select count(*) from fin_pessoas) as cadastros_agora from pes_res;
