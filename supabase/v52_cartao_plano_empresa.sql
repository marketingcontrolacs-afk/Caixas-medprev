-- =====================================================================
-- v52 · Gestão financeira: fatura do cartão de crédito, plano de contas padrão e por empresa
-- =====================================================================
-- Rode no SQL Editor do Supabase depois do v51. Pode rodar mais de uma vez.
-- Pedido da Carol (27/10/2026):
--   1) Cartão de crédito: uma conta do tipo "Cartão de crédito" só nas empresas que têm cartão.
--      Tudo o que foi pago com o cartão é lançado nela (fin_movimentos, com o mês da fatura).
--      No fim do mês a soma é conferida com a fatura do banco e a fatura é fechada: vira uma conta
--      a pagar (fin_titulos.fatura_id). O pagamento da fatura é uma transferência da conta bancária
--      para o cartão, então a despesa entra uma vez só (na compra, com a categoria dela).
--   2) Plano de contas padrão (com código e grupo da DRE) e por empresa: cada empresa usa o plano padrão (plano_contas, o mesmo para todas)
--      ou um plano próprio (fin_plano), escolhido em Gestão financeira › Cadastros › Plano de contas.

-- cartão: dia em que a fatura fecha, dia em que vence e a conta bancária que paga a fatura
alter table public.fin_contas add column if not exists cartao_fechamento smallint check (cartao_fechamento between 1 and 31);
alter table public.fin_contas add column if not exists cartao_vencimento smallint check (cartao_vencimento between 1 and 31);
alter table public.fin_contas add column if not exists cartao_conta_pag uuid references public.fin_contas on delete set null;

-- lançamentos no cartão: mês da fatura (dia 1), parcelas e a nota enviada pelo cliente (Financeiro › Cartão de crédito)
alter table public.fin_movimentos add column if not exists fatura date;
alter table public.fin_movimentos add column if not exists forma text;          -- forma de pagamento (Pix, Boleto...), para o relatório por forma
alter table public.fin_movimentos add column if not exists parcela smallint;
alter table public.fin_movimentos add column if not exists parcelas smallint;
alter table public.fin_movimentos add column if not exists grupo_id uuid;
alter table public.fin_movimentos add column if not exists cartao_nota_id uuid references public.cartao_notas on delete set null;
create unique index if not exists fin_mov_cartao_nota on public.fin_movimentos (cartao_nota_id, parcela) where cartao_nota_id is not null;
create index if not exists fin_mov_fatura on public.fin_movimentos (conta_id, fatura) where fatura is not null;

-- faturas fechadas (conferidas com a fatura do banco)
create table if not exists public.fin_faturas (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes on delete cascade,
  conta_id    uuid not null references public.fin_contas on delete cascade,   -- o cartão
  mes         date not null,                -- mês da fatura (dia 1)
  vencimento  date not null,
  valor       numeric(12,2) not null,       -- valor da fatura do banco
  fechada_em  timestamptz not null default now(),
  fechada_por uuid references auth.users default auth.uid(),
  unique (conta_id, mes)
);
alter table public.fin_titulos add column if not exists fatura_id uuid references public.fin_faturas on delete set null;
create unique index if not exists fin_titulos_fatura on public.fin_titulos (fatura_id) where fatura_id is not null;

-- plano de contas próprio da empresa
alter table public.clientes add column if not exists plano_proprio boolean not null default false;
create table if not exists public.fin_plano (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes on delete cascade,
  codigo      text,
  categoria   text not null,
  tipo        text not null default 'Despesa' check (tipo in ('Despesa','Receita')),
  ativo       boolean not null default true,
  unique (cliente_id, categoria)
);

alter table public.fin_faturas enable row level security;
alter table public.fin_plano   enable row level security;
drop policy if exists esc_tudo on public.fin_faturas;
create policy esc_tudo on public.fin_faturas for all using (eh_escritorio()) with check (eh_escritorio());
drop policy if exists esc_tudo on public.fin_plano;
create policy esc_tudo on public.fin_plano   for all using (eh_escritorio()) with check (eh_escritorio());
grant select, insert, update, delete on public.fin_faturas, public.fin_plano to authenticated;

-- ---------------------------------------------------------------------
-- Plano de contas PADRÃO (pedido da Carol, 27/10/2026): o mesmo para todas as empresas,
-- com código e grupo da DRE. Cada empresa pode ter o próprio (Cadastros › Plano de contas).
-- Os códigos que já estavam preenchidos ficam guardados em codigo_antigo.
alter table public.plano_contas add column if not exists grupo text;
alter table public.plano_contas add column if not exists codigo_antigo text;
alter table public.fin_plano    add column if not exists grupo text;
update public.plano_contas set codigo_antigo=codigo where codigo is not null and codigo_antigo is null and grupo is null;
insert into public.plano_contas (categoria,codigo,grupo,tipo) values
('Recebimento de Atendimentos','1.1.01','Venda de Serviço','Receita'),
('Repasse de Cartões','1.1.02','Venda de Serviço','Receita'),
('Recebimento de Convênios','1.1.03','Venda de Serviço','Receita'),
('Sobra de Caixa','1.1.04','Venda de Serviço','Receita'),
('Outros Recebimentos','1.2.01','Outros Recebimentos','Receita'),
('Rendimentos de Aplicação','1.2.02','Outros Recebimentos','Receita'),
('Distribuição de Resultados - Conta Cooperativa','1.2.03','Outros Recebimentos','Receita'),
('Crédito Indevido','1.2.04','Outros Recebimentos','Receita'),
('Pendência - Verificar (entrada)','1.2.05','Outros Recebimentos','Receita'),
('Debito Indevido (Estorno)','1.3.01','Estornos','Receita'),
('Restituições (Estorno)','1.3.02','Estornos','Receita'),
('Restituições','2.1.01','Despesas de Vendas','Despesa'),
('Devolução - Banco','2.1.02','Despesas de Vendas','Despesa'),
('Salário','2.2.01','Funcionário','Despesa'),
('Adto. de Salário','2.2.02','Funcionário','Despesa'),
('13 Salário','2.2.03','Funcionário','Despesa'),
('Férias','2.2.04','Funcionário','Despesa'),
('Rescisões Trabalhistas','2.2.05','Funcionário','Despesa'),
('Benefícios do Trabalhador','2.2.06','Funcionário','Despesa'),
('Plano de Saúde','2.2.07','Funcionário','Despesa'),
('Premiação','2.2.08','Funcionário','Despesa'),
('Exames pré e demissionais','2.2.09','Funcionário','Despesa'),
('Prevenção de Riscos Laborais','2.2.10','Funcionário','Despesa'),
('Cursos e Treinamentos','2.2.11','Funcionário','Despesa'),
('Outras despesas c/ Funcionário (Uniformes...)','2.2.12','Funcionário','Despesa'),
('Aluguel de imóveis','2.3.01','DESPESAS FIXAS','Despesa'),
('Condomínios','2.3.02','DESPESAS FIXAS','Despesa'),
('Honorários Contábeis','2.3.03','DESPESAS FIXAS','Despesa'),
('Pró Labore','2.3.04','DESPESAS FIXAS','Despesa'),
('Licença ou Aluguel de Softwares','2.3.05','DESPESAS FIXAS','Despesa'),
('Locação de Máquinas e Equipamentos','2.3.06','DESPESAS FIXAS','Despesa'),
('Telefonia/ Internet/ TV a cabo','2.3.07','DESPESAS FIXAS','Despesa'),
('Serviços Financeiros e Comerciais','2.3.08','DESPESAS FIXAS','Despesa'),
('Assessoria - Medicina Ocupacional','2.3.09','DESPESAS FIXAS','Despesa'),
('Segurança e Vigilância','2.3.10','DESPESAS FIXAS','Despesa'),
('Serviço de Apoio Adm','2.3.11','DESPESAS FIXAS','Despesa'),
('Energia','2.4.01','DESPESAS VARIÁVEIS','Despesa'),
('Royalties','2.4.02','DESPESAS VARIÁVEIS','Despesa'),
('Limpeza e Conservação','2.4.03','DESPESAS VARIÁVEIS','Despesa'),
('Manutenção e Reparos','2.4.04','DESPESAS VARIÁVEIS','Despesa'),
('Material de Expediente/ Escritorio','2.4.05','DESPESAS VARIÁVEIS','Despesa'),
('Material de Informática/Telefonia e Manutenção','2.4.06','DESPESAS VARIÁVEIS','Despesa'),
('Lanches, Refeições, Copa e Cozinha','2.4.07','DESPESAS VARIÁVEIS','Despesa'),
('Combustíveis e Lubrificantes','2.4.08','DESPESAS VARIÁVEIS','Despesa'),
('Manutenção de Veículos','2.4.09','DESPESAS VARIÁVEIS','Despesa'),
('Estacionamentos','2.4.10','DESPESAS VARIÁVEIS','Despesa'),
('Serviço de Transporte','2.4.11','DESPESAS VARIÁVEIS','Despesa'),
('Correio','2.4.12','DESPESAS VARIÁVEIS','Despesa'),
('Cartório','2.4.13','DESPESAS VARIÁVEIS','Despesa'),
('Certificado Digital','2.4.14','DESPESAS VARIÁVEIS','Despesa'),
('Bens de Pequeno Valor','2.4.15','DESPESAS VARIÁVEIS','Despesa'),
('Brindes','2.4.16','DESPESAS VARIÁVEIS','Despesa'),
('Confraternizações','2.4.17','DESPESAS VARIÁVEIS','Despesa'),
('Consultoria Financeira','2.4.18','DESPESAS VARIÁVEIS','Despesa'),
('Consultoria de Equipe','2.4.19','DESPESAS VARIÁVEIS','Despesa'),
('Consultoria em T.I.','2.4.20','DESPESAS VARIÁVEIS','Despesa'),
('Honorários advocatícios','2.4.21','DESPESAS VARIÁVEIS','Despesa'),
('Despesas com Viagens','2.4.22','DESPESAS VARIÁVEIS','Despesa'),
('Hospedagem','2.4.23','DESPESAS VARIÁVEIS','Despesa'),
('Adiantamento de Fornecedor','2.4.24','DESPESAS VARIÁVEIS','Despesa'),
('Cartão de Crédito (Fatura)','2.4.25','DESPESAS VARIÁVEIS','Despesa'),
('Distribuição de Lucros','2.4.26','DESPESAS VARIÁVEIS','Despesa'),
('Debito Indevido','2.4.27','DESPESAS VARIÁVEIS','Despesa'),
('Pendência - Verificar','2.4.28','DESPESAS VARIÁVEIS','Despesa'),
('Outras despesas','2.4.29','DESPESAS VARIÁVEIS','Despesa'),
('DAS - Simples Nacional','2.5.01','Tributos','Despesa'),
('INSS','2.5.02','Tributos','Despesa'),
('IRRF Folha','2.5.03','Tributos','Despesa'),
('INSS + IR Folha + IR Aluguel','2.5.04','Tributos','Despesa'),
('FGTS','2.5.05','Tributos','Despesa'),
('PIS','2.5.06','Tributos','Despesa'),
('ISS - Retido','2.5.07','Tributos','Despesa'),
('1708 - IR Retenção','2.5.08','Tributos','Despesa'),
('3208 - IRRF Aluguel','2.5.09','Tributos','Despesa'),
('5952 - PIS / Cofins / CSLL Retenção','2.5.10','Tributos','Despesa'),
('Taxas Municipais (IPTU, Vigilância, Bombeiros, Alvará, Lixo)','2.5.11','Tributos','Despesa'),
('Taxa Detran (Despachante/ Transferência/ Emplacamento)','2.5.12','Tributos','Despesa'),
('Tributos diversos','2.5.13','Tributos','Despesa'),
('Tarifas Bancárias','2.6.01','DESPESAS BANCÁRIAS E ADQUIRENTES','Despesa'),
('Tarifas de Cartões','2.6.02','DESPESAS BANCÁRIAS E ADQUIRENTES','Despesa'),
('Manutenção de conta','2.6.03','DESPESAS BANCÁRIAS E ADQUIRENTES','Despesa'),
('Antecipação de Recebíveis','2.6.04','DESPESAS BANCÁRIAS E ADQUIRENTES','Despesa'),
('Empréstimos e Financiamentos','2.6.05','DESPESAS BANCÁRIAS E ADQUIRENTES','Despesa'),
('Consórcios','2.6.06','DESPESAS BANCÁRIAS E ADQUIRENTES','Despesa'),
('Seguro Empresarial','2.6.07','DESPESAS BANCÁRIAS E ADQUIRENTES','Despesa'),
('Seguros de Bens','2.6.08','DESPESAS BANCÁRIAS E ADQUIRENTES','Despesa'),
('Ações de Marketing e Publicidade','2.7.01','Investimentos','Despesa'),
('Imobilizado','2.7.02','Investimentos','Despesa'),
('Reformas','2.7.03','Investimentos','Despesa'),
('Investimento','2.7.04','Investimentos','Despesa'),
('Investimento Chopinzinho','2.7.05','Investimentos','Despesa'),
('Investimento Coronel Vivida','2.7.06','Investimentos','Despesa'),
('Plano de Integralização Sicredi','2.7.07','Investimentos','Despesa'),
('Falta de Caixa','2.8.01','Ajustes de caixa','Despesa'),
('Depósito Bancário','2.8.02','Ajustes de caixa','Despesa')
on conflict (categoria) do update set codigo=excluded.codigo,grupo=excluded.grupo,tipo=excluded.tipo;
-- categorias antigas que não estão no padrão ficam no fim, sem código (o código antigo continua em codigo_antigo)
update public.plano_contas set codigo=null where grupo is null;

-- conta a pagar prevista (repetida todo mês): fica com o alerta "falta o boleto/nota" até chegar o documento
alter table public.fin_titulos add column if not exists previsto boolean not null default false;

select 'Atualização v52 (cartão de crédito e plano de contas por empresa) concluída' as resultado;
