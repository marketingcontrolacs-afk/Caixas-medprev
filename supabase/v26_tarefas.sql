-- =====================================================================
-- v26 · Tarefas e recados (quadro Kanban com conversa em cada tarefa)
-- =====================================================================
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Pedido da Carol (25/10/2026): módulo de comunicação e tarefas, estilo Kanban.
--   Colunas: A fazer -> Em andamento -> Aguardando cliente -> Concluída.
--   O escritório vê todas as tarefas, de todas as empresas, e as tarefas internas (sem empresa ou marcadas
--   como internas). O usuário do cliente com acesso "tarefas" vê as tarefas da empresa dele que não são internas:
--   com "Lançamento" ele abre tarefa nova, move os cartões e escreve na conversa; com "Consulta" só lê.
--   Na conversa o escritório pode deixar nota interna, que o cliente não vê.
--   Cada mudança de coluna fica registrada na conversa. Quem não abriu a tarefa desde a última mensagem vê o aviso.

-- Módulo novo na tabela de acessos
alter table public.acessos drop constraint if exists acessos_modulo_check;
alter table public.acessos add constraint acessos_modulo_check
  check (modulo in ('caixa','pagar','cartao','tesouraria','ferias','folha','repasse','tarefas'));

create table if not exists public.tarefas (
  id               uuid primary key default gen_random_uuid(),
  cliente_id       uuid references public.clientes on delete set null,   -- vazio = tarefa interna da Controlacs
  titulo           text not null,
  descricao        text,
  status           text not null default 'afazer' check (status in ('afazer','andamento','cliente','concluida')),
  prioridade       text not null default 'normal' check (prioridade in ('baixa','normal','alta','urgente')),
  prazo            date,
  responsavel      uuid references auth.users on delete set null,
  responsavel_nome text,          -- preenchido sozinho (o cliente não lê a tabela de perfis)
  interna          boolean not null default false,   -- só o escritório vê
  ordem            double precision not null default extract(epoch from now()),
  arquivada        boolean not null default false,
  criado_por       uuid references auth.users default auth.uid(),
  criado_por_nome  text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  concluida_em     timestamptz
);
create index if not exists tarefas_cliente on public.tarefas(cliente_id, arquivada);

create table if not exists public.tarefa_comentarios (
  id            uuid primary key default gen_random_uuid(),
  tarefa_id     uuid not null references public.tarefas on delete cascade,
  cliente_id    uuid,             -- preenchido sozinho, igual ao da tarefa
  texto         text,
  interno       boolean not null default false,   -- nota interna do escritório
  sistema       boolean not null default false,   -- registro automático (mudança de coluna)
  anexo_caminho text,
  anexo_nome    text,
  autor         uuid references auth.users default auth.uid(),
  autor_nome    text,
  criado_em     timestamptz not null default now(),
  check (coalesce(texto,'') <> '' or anexo_caminho is not null)
);
create index if not exists tarefa_comentarios_tarefa on public.tarefa_comentarios(tarefa_id, criado_em);

-- Até quando cada usuário já leu cada tarefa (para o aviso de mensagem nova)
create table if not exists public.tarefa_leituras (
  user_id   uuid not null references auth.users on delete cascade default auth.uid(),
  tarefa_id uuid not null references public.tarefas on delete cascade,
  lido_em   timestamptz not null default now(),
  primary key (user_id, tarefa_id)
);

create or replace function public.nome_usuario(u uuid) returns text
language sql stable security definer set search_path = public as
$$ select coalesce(nullif(nome,''), email) from perfis where user_id = u $$;

-- Preenche os nomes e as datas; o usuário do cliente não muda a empresa, o responsável nem a tarefa interna
create or replace function public.tarefa_antes() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if not eh_escritorio() then
    if tg_op = 'INSERT' then
      if new.cliente_id is null then raise exception 'Escolha a empresa da tarefa'; end if;
      new.interna := false; new.responsavel := null; new.arquivada := false;
    else
      new.cliente_id := old.cliente_id; new.interna := old.interna; new.responsavel := old.responsavel;
      new.arquivada := old.arquivada; new.criado_por := old.criado_por;
    end if;
  end if;
  if new.cliente_id is null then new.interna := true; end if;
  if tg_op = 'INSERT' then
    new.criado_por_nome := nome_usuario(new.criado_por);
  end if;
  if tg_op = 'INSERT' or new.responsavel is distinct from old.responsavel then
    new.responsavel_nome := nome_usuario(new.responsavel);
  end if;
  if new.status = 'concluida' and (tg_op = 'INSERT' or old.status <> 'concluida') then new.concluida_em := now(); end if;
  if new.status <> 'concluida' then new.concluida_em := null; end if;
  new.atualizado_em := now();
  return new;
end $$;
drop trigger if exists tarefa_antes on public.tarefas;
create trigger tarefa_antes before insert or update on public.tarefas
  for each row execute function public.tarefa_antes();

-- Mudança de coluna fica registrada na conversa
create or replace function public.tarefa_mudou() returns trigger
language plpgsql security definer set search_path = public as
$$ declare nomes jsonb := '{"afazer":"A fazer","andamento":"Em andamento","cliente":"Aguardando cliente","concluida":"Concluída"}';
begin
  if new.status is distinct from old.status then
    insert into tarefa_comentarios(tarefa_id, texto, sistema, autor)
    values (new.id, 'Moveu de “' || (nomes->>old.status) || '” para “' || (nomes->>new.status) || '”', true, auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists tarefa_mudou on public.tarefas;
create trigger tarefa_mudou after update of status on public.tarefas
  for each row execute function public.tarefa_mudou();

create or replace function public.comentario_antes() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  new.cliente_id := (select cliente_id from tarefas where id = new.tarefa_id);
  if not eh_escritorio() then new.interno := false; end if;
  new.autor_nome := nome_usuario(new.autor);
  return new;
end $$;
drop trigger if exists comentario_antes on public.tarefa_comentarios;
create trigger comentario_antes before insert on public.tarefa_comentarios
  for each row execute function public.comentario_antes();

-- Mensagem nova numa tarefa também a traz para o topo das atualizações
create or replace function public.comentario_depois() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  if not new.sistema then update tarefas set atualizado_em = now() where id = new.tarefa_id; end if;
  return new;
end $$;
drop trigger if exists comentario_depois on public.tarefa_comentarios;
create trigger comentario_depois after insert on public.tarefa_comentarios
  for each row execute function public.comentario_depois();

-- Tarefa que o usuário pode ver (o cliente nunca vê as internas)
create or replace function public.ve_tarefa(t uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select eh_escritorio() or exists(select 1 from tarefas where id = t and not interna and cliente_id is not null and pode_ver(cliente_id,'tarefas')) $$;

alter table public.tarefas            enable row level security;
alter table public.tarefa_comentarios enable row level security;
alter table public.tarefa_leituras    enable row level security;

drop policy if exists esc_tudo on public.tarefas;
create policy esc_tudo on public.tarefas for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.tarefas;
create policy op_ver on public.tarefas for select using (not interna and pode_ver(cliente_id,'tarefas'));
drop policy if exists op_criar on public.tarefas;
create policy op_criar on public.tarefas for insert with check (pode_lancar(cliente_id,'tarefas'));
drop policy if exists op_mover on public.tarefas;
create policy op_mover on public.tarefas for update
  using (not interna and pode_lancar(cliente_id,'tarefas')) with check (pode_lancar(cliente_id,'tarefas'));

drop policy if exists esc_tudo on public.tarefa_comentarios;
create policy esc_tudo on public.tarefa_comentarios for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.tarefa_comentarios;
create policy op_ver on public.tarefa_comentarios for select using (not interno and ve_tarefa(tarefa_id));
drop policy if exists op_escrever on public.tarefa_comentarios;
create policy op_escrever on public.tarefa_comentarios for insert
  with check (autor = auth.uid() and not sistema and ve_tarefa(tarefa_id)
              and exists(select 1 from tarefas t where t.id = tarefa_id and pode_lancar(t.cliente_id,'tarefas')));

drop policy if exists meu on public.tarefa_leituras;
create policy meu on public.tarefa_leituras for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Tarefas com novidade para quem está logado: mensagens de outras pessoas depois da última leitura,
-- ou tarefa aberta por outra pessoa e ainda não lida. Respeita as regras de acesso de quem chama.
create or replace function public.tarefas_novidades()
returns table(tarefa_id uuid, mensagens bigint, nova boolean)
language sql stable set search_path = public as
$$ select t.id,
          (select count(*) from tarefa_comentarios c
            where c.tarefa_id = t.id and c.autor is distinct from auth.uid() and not c.sistema
              and c.criado_em > coalesce(l.lido_em, '-infinity')),
          l.lido_em is null and t.criado_por is distinct from auth.uid()
   from tarefas t
   left join tarefa_leituras l on l.tarefa_id = t.id and l.user_id = auth.uid()
   where not t.arquivada and (t.status <> 'concluida' or t.concluida_em > now() - interval '30 days')
     and ((l.lido_em is null and t.criado_por is distinct from auth.uid())
          or exists(select 1 from tarefa_comentarios c
                     where c.tarefa_id = t.id and c.autor is distinct from auth.uid() and not c.sistema
                       and c.criado_em > coalesce(l.lido_em, '-infinity'))) $$;

-- Anexos das conversas no bucket "anexos": <empresa>/tarefas/... (tarefa sem empresa usa a pasta 00000000-...)
create or replace function public.modulo_do_arquivo(nome text) returns text
language sql immutable as
$$ select case when (string_to_array(nome,'/'))[2] in ('pagar','cartao','tesouraria','tarefas') then (string_to_array(nome,'/'))[2] else 'caixa' end $$;

grant select, insert, update, delete on public.tarefas, public.tarefa_comentarios, public.tarefa_leituras to authenticated;
grant execute on all functions in schema public to authenticated;

notify pgrst, 'reload schema';

select 'Tarefas instaladas' as resultado, (select count(*) from public.tarefas) as tarefas;
