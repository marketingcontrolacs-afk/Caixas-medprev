-- =====================================================================
-- v61 · Parceiros entram sozinhos em Clientes e fornecedores
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez. Precisa da v44 e da v58.
-- Pedido da Carol (29/10/2026): o parceiro cadastrado em "Parceiros: cadastro e alterações"
-- vai automaticamente para a lista de fornecedores da empresa.
-- - Se já existe um fornecedor com o mesmo nome na empresa (ou em todas), o parceiro é ligado a ele.
-- - Senão, cria o fornecedor com o nome, a conta e o Pix do parceiro.
-- - Quando a conta do parceiro muda (alteração aplicada) ou ele fica inativo, o fornecedor acompanha.
-- - Nada aqui impede salvar o parceiro: se o fornecedor não puder ser criado, o parceiro salva igual.

alter table public.fin_pessoas add column if not exists parceiro_id uuid references public.parceiros on delete set null;
create unique index if not exists fin_pessoas_parceiro on public.fin_pessoas (parceiro_id) where parceiro_id is not null;

create or replace function public.parceiro_para_fornecedor(p public.parceiros) returns void
language plpgsql security definer set search_path = public as
$$ declare f fin_pessoas; doc text := case when coalesce(trim(p.titular),'') = '' then nullif(trim(p.cpf_cnpj),'') end;
begin
  select * into f from fin_pessoas where parceiro_id = p.id;
  if not found then
    select * into f from fin_pessoas o where o.parceiro_id is null and pessoa_chave(o.nome) = pessoa_chave(p.nome)
       and (o.cliente_id = p.cliente_id or o.cliente_id is null)
     order by (o.cliente_id is null), o.criado_em limit 1;
  end if;
  if f.id is not null then
    update fin_pessoas set parceiro_id = p.id,
           papel = case when papel = 'cliente' then 'ambos' else papel end,
           pix_tipo = coalesce(p.pix_tipo, pix_tipo), pix_chave = coalesce(p.pix_chave, pix_chave),
           banco = coalesce(p.banco, banco), agencia = coalesce(p.agencia, agencia), conta = coalesce(p.conta, conta),
           ativo = case when f.cliente_id is null then ativo else p.ativo end
     where id = f.id;
    return;
  end if;
  begin
    insert into fin_pessoas (cliente_id, papel, nome, documento, pix_tipo, pix_chave, banco, agencia, conta, ativo, obs, parceiro_id)
    values (p.cliente_id, 'fornecedor', p.nome, doc, p.pix_tipo, p.pix_chave, p.banco, p.agencia, p.conta, p.ativo,
            'Parceiro (repasses)' || coalesce(' · ' || nullif(trim(p.especialidade),''), ''), p.id);
  exception when others then
    -- o CPF/CNPJ já está em outro cadastro: cria sem o documento
    begin
      insert into fin_pessoas (cliente_id, papel, nome, pix_tipo, pix_chave, banco, agencia, conta, ativo, obs, parceiro_id)
      values (p.cliente_id, 'fornecedor', p.nome, p.pix_tipo, p.pix_chave, p.banco, p.agencia, p.conta, p.ativo, 'Parceiro (repasses)', p.id);
    exception when others then raise notice 'Parceiro % não entrou nos fornecedores: %', p.nome, sqlerrm;
    end;
  end;
end $$;

create or replace function public.parceiro_fornecedor_trg() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  begin
    -- nome mudou: o fornecedor ligado acompanha (se o nome novo não bater com outro cadastro)
    if tg_op = 'UPDATE' and new.nome is distinct from old.nome then
      update fin_pessoas set nome = new.nome where parceiro_id = new.id and cliente_id is not null;
    end if;
  exception when others then raise notice 'Nome do fornecedor não mudou: %', sqlerrm;
  end;
  perform parceiro_para_fornecedor(new);
  return null;
end $$;
drop trigger if exists parceiro_fornecedor on public.parceiros;
create trigger parceiro_fornecedor after insert or update of nome, cpf_cnpj, titular, banco, agencia, conta, pix_tipo, pix_chave, ativo
  on public.parceiros for each row execute function public.parceiro_fornecedor_trg();

-- os parceiros que já estão cadastrados
do $$ declare p public.parceiros; begin
  for p in select * from public.parceiros order by criado_em loop perform public.parceiro_para_fornecedor(p); end loop;
end $$;

notify pgrst, 'reload schema';

select (select count(*) from public.parceiros) as parceiros,
       (select count(*) from public.fin_pessoas where parceiro_id is not null) as ligados_a_fornecedores;
