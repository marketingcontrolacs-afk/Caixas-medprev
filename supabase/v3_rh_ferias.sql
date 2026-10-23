-- Portal do Cliente (Controlacs) - atualização v3: RH / Férias (23/10/2026)
-- Rodar depois do schema.sql (v1) e do v2_modulos.sql. Pode rodar mais de uma vez.
-- Cadastro de funcionários, períodos aquisitivos e programação de férias.
-- O cliente informa a venda total e o gozo real; o sistema separa venda legal (até 1/3)
-- e venda por fora (controle interno) e monta as datas que vão para a contabilidade.
-- O escritório sempre confere a programação antes de enviar à contabilidade.
-- Acessos: módulos novos "ferias" e "folha" (a folha vem numa próxima atualização).
-- Ninguém recebe acesso automático: o escritório escolhe em Configurações > Acessos.

-- Módulos novos na tabela de acessos
alter table public.acessos drop constraint if exists acessos_modulo_check;
alter table public.acessos add constraint acessos_modulo_check
  check (modulo in ('caixa','pagar','cartao','tesouraria','ferias','folha'));

-- Empresas: serviços contratados e município (para os feriados)
alter table public.clientes add column if not exists bpo_financeiro boolean not null default true;
alter table public.clientes add column if not exists bpo_rh         boolean not null default false;
alter table public.clientes add column if not exists municipio      text;
alter table public.clientes add column if not exists uf             text not null default 'SC';

create table if not exists public.funcionarios (
  id                 uuid primary key default gen_random_uuid(),
  cliente_id         uuid not null references public.clientes,
  matricula          text not null,
  nome               text not null,
  admissao           date,
  situacao           text not null default 'Ativo' check (situacao in ('Ativo','Afastado','Desligado')),
  afastado_desde     date,
  motivo_afastamento text,
  desligado_em       date,
  operador_caixa     boolean not null default false,  -- recebe quebra de caixa fixa (folha)
  obs                text,
  unique (cliente_id, matricula)
);

-- Um por período aquisitivo. Mantido pelo escritório (fonte: relatório da contabilidade).
-- Fim do aquisitivo, limite concessivo, dias de direito e saldo são calculados na v_ferias.
create table if not exists public.ferias_periodos (
  id                    uuid primary key default gen_random_uuid(),
  funcionario_id        uuid not null references public.funcionarios on delete cascade,
  inicio_aquisitivo     date not null,   -- como no sistema de folha (pode diferir da admissão)
  faltas_injustificadas int  not null default 0 check (faltas_injustificadas >= 0),
  ja_gozados            int  not null default 0 check (ja_gozados >= 0),  -- gozados sem data informada
  quitado               boolean not null default false,  -- férias geradas pela contabilidade
  quitado_em            date,
  obs                   text,
  unique (funcionario_id, inicio_aquisitivo)
);

-- Programação de um período: o que o cliente informa e o andamento da conferência
create table if not exists public.ferias_programacoes (
  id              uuid primary key default gen_random_uuid(),
  periodo_id      uuid not null unique references public.ferias_periodos on delete cascade,
  venda_total     int  not null default 0 check (venda_total between 0 and 30),
  status          text not null default 'Proposta'
                  check (status in ('Proposta','Devolvida','Aprovada','Enviada','Gerada')),
  nota_escritorio text,
  obs             text,
  proposto_por    uuid references auth.users default auth.uid(),
  proposto_em     timestamptz not null default now(),
  aprovado_por    uuid references auth.users,
  aprovado_em     timestamptz
);

-- Parcelas de gozo, com as datas reais que o cliente informa.
-- soma_por_fora: a parcela em que a venda por fora é somada para a contabilidade.
create table if not exists public.ferias_parcelas (
  id             uuid primary key default gen_random_uuid(),
  programacao_id uuid not null references public.ferias_programacoes on delete cascade,
  ordem          int  not null check (ordem between 1 and 3),
  inicio         date not null,
  dias           int  not null check (dias between 1 and 30),
  soma_por_fora  boolean not null default false,
  unique (programacao_id, ordem)
);
create unique index if not exists ferias_parcelas_um_por_fora
  on public.ferias_parcelas(programacao_id) where soma_por_fora;

-- Feriados: nacional (uf e municipio vazios), estadual (uf) ou municipal (uf + municipio)
create table if not exists public.feriados (
  data      date not null,
  nome      text not null,
  uf        text,
  municipio text,
  unique nulls not distinct (data, uf, municipio)
);

-- ---------------------------------------------------------------------
-- Regras de cálculo
-- ---------------------------------------------------------------------

-- Dias de direito conforme as faltas injustificadas (CLT art. 130)
create or replace function public.dias_direito(faltas int) returns int
language sql immutable as
$$ select case when faltas <= 5 then 30 when faltas <= 14 then 24
               when faltas <= 23 then 18 when faltas <= 32 then 12 else 0 end $$;

-- Dia de folga ou feriado para a empresa (descanso semanal = domingo)
create or replace function public.dia_sem_trabalho(cli uuid, d date) returns boolean
language sql stable security definer set search_path = public as
$$ select extract(isodow from d) = 7 or exists(
     select 1 from feriados f, clientes c
     where c.id = cli and f.data = d
       and (f.uf is null or (f.uf = c.uf and (f.municipio is null or f.municipio = c.municipio)))) $$;

-- Férias não podem começar em folga/feriado nem nos 2 dias antes deles (CLT art. 134 §3º)
create or replace function public.inicio_ferias_valido(cli uuid, d date) returns boolean
language sql stable as
$$ select not (dia_sem_trabalho(cli, d) or dia_sem_trabalho(cli, d + 1) or dia_sem_trabalho(cli, d + 2)) $$;

create or replace function public.proximo_inicio_valido(cli uuid, d date) returns date
language sql stable as
$$ select min(x)::date from generate_series(d, d + 60, interval '1 day') x
   where inicio_ferias_valido(cli, x::date) $$;

-- Períodos com saldo, situação e prazos (mesmas regras da planilha de controle)
create or replace view public.v_ferias with (security_invoker = on) as
with base as (
  select p.*, f.cliente_id, f.matricula, f.nome, f.admissao, f.situacao as situacao_funcionario,
         pr.id as programacao_id, pr.status as status_programacao, coalesce(pr.venda_total, 0) as venda_total,
         (p.inicio_aquisitivo + interval '1 year' - interval '1 day')::date  as fim_aquisitivo,
         (p.inicio_aquisitivo + interval '2 years' - interval '1 day')::date as limite_concessivo,
         dias_direito(p.faltas_injustificadas) as direito,
         coalesce((select sum(x.dias) from ferias_parcelas x where x.programacao_id = pr.id), 0)::int as gozo_programado,
         (select max(x.inicio + x.dias - 1) from ferias_parcelas x where x.programacao_id = pr.id) as fim_gozo
  from ferias_periodos p
  join funcionarios f on f.id = p.funcionario_id
  left join ferias_programacoes pr on pr.periodo_id = p.id and pr.status <> 'Devolvida'
), calc as (
  select b.*,
         least(b.venda_total, b.direito / 3) as venda_legal,
         b.venda_total - least(b.venda_total, b.direito / 3) as venda_por_fora,
         b.direito - b.ja_gozados - b.venda_total - b.gozo_programado as saldo
  from base b
)
select c.*,
       case when c.saldo > 0 then c.limite_concessivo - c.saldo + 1 end as iniciar_ate,
       case
         when c.situacao_funcionario = 'Desligado' then 'Desligado'
         when c.situacao_funcionario = 'Afastado'  then 'Afastado'
         when c.quitado then 'Quitada'
         when c.saldo <= 0 then case when c.fim_gozo >= current_date then 'Programada' else 'Quitada' end
         when current_date <= c.fim_aquisitivo then 'Em aquisição'
         when current_date > c.limite_concessivo then 'Vencida'
         when current_date > c.limite_concessivo - c.saldo + 1 then 'Prazo estourado'
         when c.limite_concessivo - c.saldo + 1 - current_date <= 60 then 'Vence em 60 dias'
         else 'Disponível'
       end as situacao
from calc c;

-- Parcelas com as datas reais e as datas que vão para a contabilidade
create or replace view public.v_ferias_parcelas with (security_invoker = on) as
select x.*, v.periodo_id, v.cliente_id, v.matricula, v.nome, v.status,
       x.inicio + x.dias - 1 as fim_real,
       x.dias + case when x.soma_por_fora then v.venda_por_fora else 0 end as dias_contabilidade,
       x.inicio + x.dias + case when x.soma_por_fora then v.venda_por_fora else 0 end - 1 as fim_contabilidade,
       x.inicio - 30 as aviso_ate,
       x.inicio - 2  as pagar_ate,
       inicio_ferias_valido(v.cliente_id, x.inicio) as inicio_valido
from ferias_parcelas x
join (select pr.id, pr.periodo_id, pr.status, vf.cliente_id, vf.matricula, vf.nome, vf.venda_por_fora
      from ferias_programacoes pr join v_ferias vf on vf.id = pr.periodo_id) v on v.id = x.programacao_id;

-- ---------------------------------------------------------------------
-- Regras de acesso
-- ---------------------------------------------------------------------

create or replace function public.cliente_do_periodo(per uuid) returns uuid
language sql stable security definer set search_path = public as
$$ select f.cliente_id from ferias_periodos p join funcionarios f on f.id = p.funcionario_id where p.id = per $$;

create or replace function public.cliente_da_programacao(prog uuid) returns uuid
language sql stable security definer set search_path = public as
$$ select cliente_do_periodo(periodo_id) from ferias_programacoes where id = prog $$;

-- Programação ainda nas mãos do cliente (não aprovada pelo escritório)
create or replace function public.programacao_aberta(prog uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select coalesce((select status in ('Proposta','Devolvida') from ferias_programacoes where id = prog), true) $$;

-- A data de início tem que valer para o recibo: bloqueia início perto de folga ou feriado
create or replace function public.checar_inicio_ferias() returns trigger
language plpgsql security definer set search_path = public as
$$ declare cli uuid := cliente_da_programacao(new.programacao_id);
begin
  if (tg_op = 'INSERT' or new.inicio is distinct from old.inicio)
     and not inicio_ferias_valido(cli, new.inicio) then
    raise exception 'As férias não podem começar em %: é folga/feriado ou um dos 2 dias antes. Próxima data possível: %.',
      to_char(new.inicio,'DD/MM/YYYY'), to_char(proximo_inicio_valido(cli, new.inicio),'DD/MM/YYYY');
  end if;
  return new;
end $$;
drop trigger if exists checa_inicio on public.ferias_parcelas;
create trigger checa_inicio before insert or update on public.ferias_parcelas
  for each row execute function public.checar_inicio_ferias();

alter table public.funcionarios        enable row level security;
alter table public.ferias_periodos     enable row level security;
alter table public.ferias_programacoes enable row level security;
alter table public.ferias_parcelas     enable row level security;
alter table public.feriados            enable row level security;

-- Escritório faz tudo
drop policy if exists esc_tudo on public.funcionarios;
create policy esc_tudo on public.funcionarios        for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.ferias_periodos;
create policy esc_tudo on public.ferias_periodos     for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.ferias_programacoes;
create policy esc_tudo on public.ferias_programacoes for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.ferias_parcelas;
create policy esc_tudo on public.ferias_parcelas     for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.feriados;
create policy esc_tudo on public.feriados            for all using (eh_escritorio()) with check (eh_escritorio());

-- Funcionários e períodos: cliente vê com acesso a férias ou folha; só o escritório altera
drop policy if exists op_ver on public.funcionarios;
create policy op_ver on public.funcionarios for select
  using (pode_ver(cliente_id,'ferias') or pode_ver(cliente_id,'folha'));
drop policy if exists op_ver on public.ferias_periodos;
create policy op_ver on public.ferias_periodos for select
  using (pode_ver(cliente_do_periodo(id),'ferias'));

-- Programação: cliente com "lançamento" propõe e corrige até o escritório aprovar
drop policy if exists op_ver on public.ferias_programacoes;
create policy op_ver on public.ferias_programacoes for select
  using (pode_ver(cliente_do_periodo(periodo_id),'ferias'));
drop policy if exists op_criar on public.ferias_programacoes;
create policy op_criar on public.ferias_programacoes for insert
  with check (pode_lancar(cliente_do_periodo(periodo_id),'ferias') and status = 'Proposta');
drop policy if exists op_editar on public.ferias_programacoes;
create policy op_editar on public.ferias_programacoes for update
  using (pode_lancar(cliente_do_periodo(periodo_id),'ferias') and status in ('Proposta','Devolvida'))
  with check (pode_lancar(cliente_do_periodo(periodo_id),'ferias') and status = 'Proposta'
              and aprovado_por is null);
drop policy if exists op_apagar on public.ferias_programacoes;
create policy op_apagar on public.ferias_programacoes for delete
  using (pode_lancar(cliente_do_periodo(periodo_id),'ferias') and status in ('Proposta','Devolvida'));

drop policy if exists op_ver on public.ferias_parcelas;
create policy op_ver on public.ferias_parcelas for select
  using (pode_ver(cliente_da_programacao(programacao_id),'ferias'));
drop policy if exists op_gravar on public.ferias_parcelas;
create policy op_gravar on public.ferias_parcelas for all
  using (pode_lancar(cliente_da_programacao(programacao_id),'ferias') and programacao_aberta(programacao_id))
  with check (pode_lancar(cliente_da_programacao(programacao_id),'ferias') and programacao_aberta(programacao_id));

-- Feriados: todos os usuários logados consultam
drop policy if exists todos_ver on public.feriados;
create policy todos_ver on public.feriados for select using (auth.uid() is not null);

-- ---------------------------------------------------------------------
-- Dados iniciais
-- ---------------------------------------------------------------------

-- Empresas da Oliveira (3 CNPJs). A Oliveira SJ já existia.
insert into public.clientes(nome, municipio, bpo_rh) values
  ('Oliveira Biguaçu','Biguaçu',true),
  ('Oliveira Palhoça','Palhoça',true)
on conflict (nome) do nothing;
update public.clientes set municipio = coalesce(municipio,'São José'), bpo_rh = true where nome = 'Oliveira SJ';

-- Feriados nacionais 2026 e 2027. Estaduais e municipais: o escritório cadastra.
insert into public.feriados(data, nome) values
 ('2026-01-01','Confraternização Universal'),('2026-04-03','Sexta-feira Santa'),
 ('2026-04-21','Tiradentes'),('2026-05-01','Dia do Trabalho'),
 ('2026-09-07','Independência'),('2026-10-12','Nossa Senhora Aparecida'),
 ('2026-11-02','Finados'),('2026-11-15','Proclamação da República'),
 ('2026-11-20','Consciência Negra'),('2026-12-25','Natal'),
 ('2027-01-01','Confraternização Universal'),('2027-03-26','Sexta-feira Santa'),
 ('2027-04-21','Tiradentes'),('2027-05-01','Dia do Trabalho'),
 ('2027-09-07','Independência'),('2027-10-12','Nossa Senhora Aparecida'),
 ('2027-11-02','Finados'),('2027-11-15','Proclamação da República'),
 ('2027-11-20','Consciência Negra'),('2027-12-25','Natal')
on conflict do nothing;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

notify pgrst, 'reload schema';
select 'Atualização v3 (RH / Férias) concluída' as resultado;
