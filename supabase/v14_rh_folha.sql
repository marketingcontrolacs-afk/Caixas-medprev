-- Portal do Cliente (Controlacs) - atualização v14: RH › Folha de pagamento (24/10/2026)
-- Rodar depois do v13. Pode rodar mais de uma vez.
-- Durante o mês lançam-se as informações de cada colaborador (horas extras, faltas, adiantamento...).
-- No fechamento o escritório confere, ajusta o que precisar e baixa a planilha no modelo da contabilidade.
-- Os valores fixos (ajuda de custo, gratificação, quebra de caixa, insalubridade, VA e VT) ficam no
-- cadastro do colaborador e entram sozinhos todo mês. Rescisões têm planilha própria.

-- Colaborador: cargo e valores fixos da folha. Matrícula passa a ser opcional (empresas só de RH
-- começam pela folha; a matrícula entra depois, pela importação de férias).
alter table public.funcionarios alter column matricula drop not null;
alter table public.funcionarios add column if not exists cargo               text;
alter table public.funcionarios add column if not exists folha_ajuda_custo   numeric(12,2);  -- R$ por mês
alter table public.funcionarios add column if not exists folha_gratificacao  numeric(6,4);   -- 0,40 = 40%
alter table public.funcionarios add column if not exists folha_quebra_cx     numeric(6,4);   -- 0,20 = 20%
alter table public.funcionarios add column if not exists folha_insalubridade numeric(6,4);   -- 0,20 = 20%
alter table public.funcionarios add column if not exists folha_va            boolean not null default true;
alter table public.funcionarios add column if not exists folha_vt            boolean not null default false;

-- Colunas da planilha de cada empresa (na ordem). Vazio = modelo padrão do site.
alter table public.clientes add column if not exists folha_colunas text[];

-- Um por empresa e mês: Aberta (lançando) -> Conferida (escritório) -> Enviada (para a contabilidade)
create table if not exists public.folha_meses (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes on delete cascade,
  competencia   date not null check (extract(day from competencia) = 1),
  status        text not null default 'Aberta' check (status in ('Aberta','Conferida','Enviada')),
  conferido_por uuid,
  conferido_em  timestamptz,
  obs           text,
  unique (cliente_id, competencia)
);

-- Cada informação lançada no mês. coluna = chave da coluna da planilha (horas_extras, faltas_dias...).
-- quantidade: horas em minutos, dias, ou valor em R$, conforme a coluna; texto quando não é número.
create table if not exists public.folha_lancamentos (
  id             uuid primary key default gen_random_uuid(),
  cliente_id     uuid not null references public.clientes on delete cascade,
  competencia    date not null check (extract(day from competencia) = 1),
  funcionario_id uuid not null references public.funcionarios on delete cascade,
  coluna         text not null,
  data           date,
  quantidade     numeric(12,2),
  texto          text,
  descricao      text,
  criado_por     uuid default auth.uid(),
  criado_em      timestamptz not null default now()
);
create index if not exists folha_lancamentos_mes on public.folha_lancamentos (cliente_id, competencia);

-- Ajuste do escritório na conferência: substitui o valor calculado daquela célula.
create table if not exists public.folha_ajustes (
  cliente_id     uuid not null references public.clientes on delete cascade,
  competencia    date not null,
  funcionario_id uuid not null references public.funcionarios on delete cascade,
  coluna         text not null,
  valor          text,
  primary key (cliente_id, competencia, funcionario_id, coluna)
);

-- Rescisão (mesmos blocos da planilha de rescisão). valores = {"va":"40","ajuda_custo":"Não",...}
create table if not exists public.folha_rescisoes (
  id             uuid primary key default gen_random_uuid(),
  cliente_id     uuid not null references public.clientes on delete cascade,
  funcionario_id uuid not null references public.funcionarios on delete cascade,
  tipo           text not null,
  data_demissao  date not null,
  ultimo_dia     date,
  aviso_multa    text,
  valores        jsonb not null default '{}'::jsonb,
  obs            text,
  status         text not null default 'Aberta' check (status in ('Aberta','Conferida','Enviada')),
  criado_por     uuid default auth.uid(),
  criado_em      timestamptz not null default now()
);

-- Mês ainda aberto para lançar? (sem linha em folha_meses = aberto)
create or replace function public.folha_aberta(cli uuid, comp date) returns boolean
language sql stable security definer set search_path = public as
$$ select coalesce((select status = 'Aberta' from folha_meses where cliente_id = cli and competencia = comp), true) $$;

-- A rescisão marca o colaborador como desligado na data da demissão
create or replace function public.folha_rescisao_desliga() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  update funcionarios set situacao = 'Desligado', desligado_em = new.data_demissao
   where id = new.funcionario_id and (situacao <> 'Desligado' or desligado_em is distinct from new.data_demissao);
  return new;
end $$;
drop trigger if exists folha_rescisao_desliga on public.folha_rescisoes;
create trigger folha_rescisao_desliga after insert or update of data_demissao, funcionario_id on public.folha_rescisoes
  for each row execute function public.folha_rescisao_desliga();

alter table public.folha_meses       enable row level security;
alter table public.folha_lancamentos enable row level security;
alter table public.folha_ajustes     enable row level security;
alter table public.folha_rescisoes   enable row level security;

drop policy if exists esc_tudo on public.folha_meses;
create policy esc_tudo on public.folha_meses for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.folha_meses;
create policy op_ver on public.folha_meses for select using (pode_ver(cliente_id,'folha'));

drop policy if exists esc_tudo on public.folha_lancamentos;
create policy esc_tudo on public.folha_lancamentos for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.folha_lancamentos;
create policy op_ver on public.folha_lancamentos for select using (pode_ver(cliente_id,'folha'));
drop policy if exists op_gravar on public.folha_lancamentos;
create policy op_gravar on public.folha_lancamentos for all
  using (pode_lancar(cliente_id,'folha') and folha_aberta(cliente_id, competencia))
  with check (pode_lancar(cliente_id,'folha') and folha_aberta(cliente_id, competencia));

drop policy if exists esc_tudo on public.folha_ajustes;
create policy esc_tudo on public.folha_ajustes for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.folha_ajustes;
create policy op_ver on public.folha_ajustes for select using (pode_ver(cliente_id,'folha'));

drop policy if exists esc_tudo on public.folha_rescisoes;
create policy esc_tudo on public.folha_rescisoes for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists op_ver on public.folha_rescisoes;
create policy op_ver on public.folha_rescisoes for select using (pode_ver(cliente_id,'folha'));
drop policy if exists op_gravar on public.folha_rescisoes;
create policy op_gravar on public.folha_rescisoes for all
  using (pode_lancar(cliente_id,'folha') and status = 'Aberta')
  with check (pode_lancar(cliente_id,'folha') and status = 'Aberta');

grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- ---------------------------------------------------------------------------
-- Clínica Viva Simon: colunas das planilhas e colaboradores da folha de 09/2026
-- ---------------------------------------------------------------------------
update public.clientes set bpo_rh = true, folha_colunas = array['ajuda_custo','gratificacao','horas_extras','quebra_cx','insalubridade',
  'va','vt','quebra_cx_desc','faltas_horas','faltas_dias','dsr','adiantamento']
 where nome = 'Clinica Simon Filial';
update public.clientes set bpo_rh = true, folha_colunas = array['ajuda_custo','gratificacao','dif_salario','quebra_cx','insalubridade',
  'va','vt','descontos_diversos','quebra_cx_desc','faltas_horas','faltas_dias','dsr','adiantamento','observacoes']
 where nome = 'Clinica Viva Simon Matriz';

-- nome, cargo, ajuda de custo, gratificação, quebra de caixa, insalubridade, VT
insert into public.funcionarios (cliente_id, nome, cargo, folha_ajuda_custo, folha_gratificacao, folha_quebra_cx, folha_insalubridade, folha_va, folha_vt)
select c.id, v.nome, v.cargo, v.ajuda, v.grat, v.qcx, v.ins, true, v.vt
  from public.clientes c
  join (values
    ('Clinica Simon Filial','Naiane','Recepcionista',null::numeric,null::numeric,0.2,null::numeric,true),
    ('Clinica Simon Filial','Giovanna','Recepcionista',null,null,0.2,null,false),
    ('Clinica Simon Filial','Jussara Garcia Rodrigues','Aux de Serv Gerais',130,null,null,0.4,false),
    ('Clinica Simon Filial','Rejane Santiago Casa Blanca','Aux de Faturamento',230.8,0.4,null,null,true),
    ('Clinica Simon Filial','Darllea do Socorro','Tec Enfermagem',130,null,null,0.2,false),
    ('Clinica Viva Simon Matriz','Filipe Marcolla Davila Borba','Atendente Call center',130,null,null,null,false),
    ('Clinica Viva Simon Matriz','Kauani Vitoria Correa Ferreira','Atendente Call center',null,null,null,null,true),
    ('Clinica Viva Simon Matriz','Larissa de Brito','Atendente Call center',130,null,null,null,false),
    ('Clinica Viva Simon Matriz','Maria Eduarda Santos','Atendente Call center',130,null,null,null,false),
    ('Clinica Viva Simon Matriz','Nathalia Martins Criminacio','Atendente Call center',null,null,null,null,true),
    ('Clinica Viva Simon Matriz','Vitória da Silva Rodrigues','Atendente Call center',null,null,null,null,true),
    ('Clinica Viva Simon Matriz','Giseli Alves Do Prado','Aux de Limpeza',130,null,null,0.4,false),
    ('Clinica Viva Simon Matriz','Rosangela Fabiano Da Silva','Aux de Limpeza',130,null,null,0.4,false),
    ('Clinica Viva Simon Matriz','Camilla Taynara De Lima Dias','Supervisora de Recepção',null,0.4,null,null,true),
    ('Clinica Viva Simon Matriz','Janaina Rodrigues','Recepcionista',null,null,0.2,null,true),
    ('Clinica Viva Simon Matriz','Elaine Claudino dos Santos','Recepcionista',null,null,0.2,null,true),
    ('Clinica Viva Simon Matriz','Janaina Souza','Recepcionista',null,null,0.2,null,true),
    ('Clinica Viva Simon Matriz','Bruna Batista da Silva','Recepcionista',null,null,0.2,null,true),
    ('Clinica Viva Simon Matriz','Alice de Souza Gonçalves','Recepcionista',null,null,0.2,null,true),
    ('Clinica Viva Simon Matriz','Pedro Vitor','Supervisor Financeiro',null,null,0.2,null,true),
    ('Clinica Viva Simon Matriz','Emanuella Valdevina Vieira','Supervisora de Call Center',545,null,null,0.2,false),
    ('Clinica Viva Simon Matriz','Debora Santos da Rosa','Tec Enfermagem',130,null,null,0.2,false),
    ('Clinica Viva Simon Matriz','Maria Eduarda Francisco Martins','Tec Enfermagem',null,null,null,0.2,true),
    ('Clinica Viva Simon Matriz','Ruth Pastl','Tec Enfermagem',null,null,null,0.2,false),
    ('Clinica Viva Simon Matriz','Cintia Roberta Amorim de Souza Ferreira','Tec Enfermagem',null,null,null,0.2,true),
    ('Clinica Viva Simon Matriz','Daniela Urbano','Tec Enfermagem',null,null,null,0.2,true),
    ('Clinica Viva Simon Matriz','Tatyana Dias Franca','Tec Enfermagem',null,null,null,0.2,false)
  ) as v(empresa,nome,cargo,ajuda,grat,qcx,ins,vt) on v.empresa = c.nome
 where not exists (select 1 from public.funcionarios f where f.cliente_id = c.id and lower(f.nome) = lower(v.nome));

update public.funcionarios set situacao = 'Afastado', afastado_desde = '2026-08-28', motivo_afastamento = 'Licença Maternidade'
 where nome = 'Tatyana Dias Franca' and situacao = 'Ativo';

-- Rescisões de outubro/2026 da planilha de rescisão (também deixam as três como desligadas)
insert into public.folha_rescisoes (cliente_id, funcionario_id, tipo, data_demissao, ultimo_dia, aviso_multa, valores)
select f.cliente_id, f.id, v.tipo, v.dem::date, v.ult::date, v.aviso, v.valores::jsonb
  from public.funcionarios f join public.clientes c on c.id = f.cliente_id and c.nome = 'Clinica Viva Simon Matriz'
  join (values
    ('Janaina Rodrigues','Pedido de demissão por parte do colaborador','2026-10-19','2026-10-18','Sim, descontar',
     '{"ajuda_custo":"Não","gratificacao":"Não","quebra_cx":"Proporcional","insalubridade":"Não","he50":"1:03","va_desc":"40","vt_desc":"159,28","quebra_cx_desc":"Não","faltas_horas":"19/10/2026"}'),
    ('Alice de Souza Gonçalves','Demissão Término de experiência','2026-10-20','2026-10-20','Não',
     '{"ajuda_custo":"Não","gratificacao":"Não","quebra_cx":"Proporcional","insalubridade":"Não","he50":"6:52","va_desc":"33","vt_desc":"129,60","quebra_cx_desc":"Não"}'),
    ('Vitória da Silva Rodrigues','Demissão Término de experiência','2026-10-19','2026-10-19','Não',
     '{"ajuda_custo":"Não","gratificacao":"Não","quebra_cx":"Não","insalubridade":"Não","va_desc":"40","vt_desc":"130,32","quebra_cx_desc":"Não","faltas_horas":"0:58"}')
  ) as v(nome,tipo,dem,ult,aviso,valores) on v.nome = f.nome
 where not exists (select 1 from public.folha_rescisoes r where r.funcionario_id = f.id);

select c.nome as empresa, count(f.*) as colaboradores,
       (select count(*) from public.folha_rescisoes r where r.cliente_id = c.id) as rescisoes
  from public.clientes c left join public.funcionarios f on f.cliente_id = c.id
 where c.nome like 'Clinica%' group by c.id, c.nome;
