-- v65: Comunicação › Projetos e melhorias
-- A equipe da Controlacs pede a criação ou a melhoria de algo (categoria, regra, cadastro, funcionalidade...)
-- e a administradora (usuário master) valida: aprova, recusa ou devolve para ajuste.
-- Só a administradora muda a situação do pedido; quem pediu edita enquanto ele aguarda validação ou ajuste.

create table if not exists public.projetos (
  id               uuid primary key default gen_random_uuid(),
  tipo             text not null default 'melhoria' check (tipo in ('categoria','regra','cadastro','funcionalidade','melhoria','correcao','outro')),
  titulo           text not null,
  descricao        text,
  motivo           text,                             -- por que precisa (o que melhora)
  cliente_id       uuid references public.clientes on delete set null,   -- empresa, quando o pedido é de uma empresa
  prioridade       text not null default 'normal' check (prioridade in ('baixa','normal','alta','urgente')),
  status           text not null default 'aguardando' check (status in ('aguardando','ajuste','aprovado','andamento','concluido','recusado')),
  resposta         text,                             -- parecer da administradora
  anexo_caminho    text,
  anexo_nome       text,
  decidido_por     uuid references auth.users,
  decidido_por_nome text,
  decidido_em      timestamptz,
  novo_para_admin  boolean not null default true,    -- novidade para a administradora (pedido novo, reenviado ou mensagem)
  novo_para_autor  boolean not null default false,   -- novidade para quem pediu (parecer ou mensagem)
  criado_por       uuid references auth.users default auth.uid(),
  criado_por_nome  text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index if not exists projetos_status on public.projetos(status);

create table if not exists public.projeto_comentarios (
  id            uuid primary key default gen_random_uuid(),
  projeto_id    uuid not null references public.projetos on delete cascade,
  texto         text,
  anexo_caminho text,
  anexo_nome    text,
  sistema       boolean not null default false,     -- registro automático (mudança de situação)
  autor         uuid references auth.users default auth.uid(),
  autor_nome    text,
  criado_em     timestamptz not null default now()
);
create index if not exists projeto_comentarios_projeto on public.projeto_comentarios(projeto_id);

-- Nomes, datas e as regras de quem muda o quê
create or replace function public.projeto_antes() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if tg_op = 'INSERT' then
    new.criado_por_nome := nome_usuario(new.criado_por);
    if not eh_admin() then
      new.status := 'aguardando'; new.resposta := null;
      new.decidido_por := null; new.decidido_por_nome := null; new.decidido_em := null;
    end if;
    new.novo_para_admin := not eh_admin(); new.novo_para_autor := false;
  elsif (to_jsonb(new) - 'novo_para_admin' - 'novo_para_autor' - 'atualizado_em')
        = (to_jsonb(old) - 'novo_para_admin' - 'novo_para_autor' - 'atualizado_em') then
    -- só as marcas de novidade (mensagem nova ou pedido aberto)
    return new;
  elsif auth.uid() is not null and not eh_admin() then
    if old.status not in ('aguardando','ajuste') then
      raise exception 'Este pedido já foi validado; só a administradora altera';
    end if;
    -- quem pediu só muda o texto; ao salvar um pedido devolvido, ele volta para validação
    new.status := 'aguardando'; new.resposta := old.resposta;
    new.decidido_por := old.decidido_por; new.decidido_por_nome := old.decidido_por_nome; new.decidido_em := old.decidido_em;
    new.criado_por := old.criado_por; new.criado_por_nome := old.criado_por_nome;
    if new.novo_para_autor is distinct from old.novo_para_autor then new.novo_para_autor := old.novo_para_autor; end if;
    new.novo_para_admin := true;
  elsif new.status is distinct from old.status or new.resposta is distinct from old.resposta then
    new.decidido_por := auth.uid(); new.decidido_por_nome := nome_usuario(auth.uid()); new.decidido_em := now();
    new.novo_para_autor := new.criado_por is distinct from auth.uid();
    new.novo_para_admin := false;
  end if;
  new.atualizado_em := now();
  return new;
end $$;
drop trigger if exists projeto_antes on public.projetos;
create trigger projeto_antes before insert or update on public.projetos
  for each row execute function public.projeto_antes();

-- Mudança de situação vira registro na conversa
create or replace function public.projeto_depois() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if new.status is distinct from old.status then
    insert into projeto_comentarios(projeto_id, texto, sistema, autor)
    values (new.id, 'mudou para ' || case new.status when 'aguardando' then 'Aguardando validação' when 'ajuste' then 'Precisa de ajuste'
      when 'aprovado' then 'Aprovado' when 'andamento' then 'Em andamento' when 'concluido' then 'Concluído' else 'Recusado' end, true, auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists projeto_depois on public.projetos;
create trigger projeto_depois after update on public.projetos
  for each row execute function public.projeto_depois();

-- Mensagem na conversa: nome do autor e novidade para o outro lado
create or replace function public.projeto_comentario_antes() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  new.autor_nome := nome_usuario(new.autor);
  if not new.sistema then
    update projetos set
      novo_para_admin = novo_para_admin or not eh_admin(),
      novo_para_autor = novo_para_autor or (eh_admin() and criado_por is distinct from auth.uid())
     where id = new.projeto_id;
  end if;
  return new;
end $$;
drop trigger if exists projeto_comentario_antes on public.projeto_comentarios;
create trigger projeto_comentario_antes before insert on public.projeto_comentarios
  for each row execute function public.projeto_comentario_antes();

-- O usuário abriu o pedido: some a novidade dele
create or replace function public.projeto_visto(p uuid) returns void
language sql security definer set search_path = public as
$$ update projetos set
     novo_para_admin = case when eh_admin() then false else novo_para_admin end,
     novo_para_autor = case when criado_por = auth.uid() then false else novo_para_autor end
    where id = p and eh_escritorio() and (eh_admin() or criado_por = auth.uid()) $$;

-- Quantos pedidos têm novidade para quem está logado (número no menu)
create or replace function public.projetos_novidades() returns bigint
language sql stable security definer set search_path = public as
$$ select count(*) from projetos
    where eh_escritorio() and ((eh_admin() and novo_para_admin) or (criado_por = auth.uid() and novo_para_autor)) $$;

alter table public.projetos            enable row level security;
alter table public.projeto_comentarios enable row level security;
-- toda a equipe vê os pedidos (evita pedido repetido); só a administradora decide
drop policy if exists esc_ver on public.projetos;
create policy esc_ver on public.projetos for select using (eh_escritorio());
drop policy if exists esc_criar on public.projetos;
create policy esc_criar on public.projetos for insert with check (eh_escritorio());
drop policy if exists editar on public.projetos;
create policy editar on public.projetos for update
  using (eh_admin() or (eh_escritorio() and criado_por = auth.uid())) with check (eh_escritorio());
drop policy if exists excluir on public.projetos;
create policy excluir on public.projetos for delete
  using (eh_admin() or (eh_escritorio() and criado_por = auth.uid() and status in ('aguardando','ajuste')));
drop policy if exists esc_ver on public.projeto_comentarios;
create policy esc_ver on public.projeto_comentarios for select using (eh_escritorio());
drop policy if exists esc_escrever on public.projeto_comentarios;
create policy esc_escrever on public.projeto_comentarios for insert
  with check (eh_escritorio() and autor = auth.uid() and not sistema);

grant select, insert, update, delete on public.projetos, public.projeto_comentarios to authenticated;
grant execute on function public.projeto_visto(uuid), public.projetos_novidades() to authenticated;
