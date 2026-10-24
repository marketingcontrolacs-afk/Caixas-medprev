-- Portal do Cliente (Controlacs) - atualização v15: RH › Colaboradores e prazos de experiência (24/10/2026)
-- Rodar depois do v14. Pode rodar mais de uma vez.
-- Dados da planilha "Informações de Colaboradores" da Clínica Viva Simon (abas Prazos, Viva Filial,
-- Viva Matriz, Escalas e Contatos). O contrato de experiência tem dois vencimentos: o fim do 1º período
-- e o fim da prorrogação (até 90 dias). Os dois ficam gravados como datas, porque nem todo contrato é 45 + 45.

alter table public.funcionarios add column if not exists nascimento         date;
alter table public.funcionarios add column if not exists fim_experiencia1   date;  -- fim do 1º período
alter table public.funcionarios add column if not exists fim_experiencia2   date;  -- fim da prorrogação
alter table public.funcionarios add column if not exists ultimo_dia_aviso   date;
alter table public.funcionarios add column if not exists prazos_obs         text;
alter table public.funcionarios add column if not exists va_valor           numeric(12,2);  -- R$ por mês
alter table public.funcionarios add column if not exists vt_valor_dia       numeric(12,2);  -- ida + volta
alter table public.funcionarios add column if not exists vt_empresa         text;
alter table public.funcionarios add column if not exists telefone           text;

-- Nomes completos (a folha de setembro trazia só o primeiro nome de alguns)
update public.funcionarios f set nome = v.novo
  from public.clientes c, (values
    ('Clinica Simon Filial','Darllea','Darllea do Socorro'),
    ('Clinica Simon Filial','Jussara','Jussara Garcia Rodrigues'),
    ('Clinica Viva Simon Matriz','Kauani Ferreira','Kauani Vitoria Correa Ferreira'),
    ('Clinica Viva Simon Matriz','Larissa','Larissa de Brito'),
    ('Clinica Viva Simon Matriz','Pedro','Pedro Vitor'),
    ('Clinica Viva Simon Matriz','Bruna Batista','Bruna Batista da Silva'),
    ('Clinica Viva Simon Matriz','Elaine','Elaine Claudino dos Santos'),
    ('Clinica Viva Simon Matriz','Cintia Roberta Amorim de S Ferreira','Cintia Roberta Amorim de Souza Ferreira')
  ) as v(empresa, antigo, novo)
 where c.id = f.cliente_id and c.nome = v.empresa and f.nome = v.antigo;

-- Colaboradores novos de outubro (Viva Matriz). Percentuais da folha ficam para o escritório conferir.
insert into public.funcionarios (cliente_id, nome, cargo, admissao, folha_ajuda_custo, folha_va, folha_vt)
select c.id, v.nome, v.cargo, v.adm::date, v.ajuda, true, v.vt
  from public.clientes c join (values
    ('Mayara Souza Gaspar Maciel','Atendente Call center','2026-10-09',130::numeric,false),
    ('Ricaele Moreira dos Anjos','Recepcionista','2026-10-13',null,true),
    ('Daniel Moreira de Almeida','Tec Enfermagem','2026-10-09',130,false),
    ('Nataniel Souza de Avila','Tec Enfermagem','2026-10-15',null,true)
  ) as v(nome,cargo,adm,ajuda,vt) on c.nome = 'Clinica Viva Simon Matriz'
 where not exists (select 1 from public.funcionarios f where f.cliente_id = c.id and lower(f.nome) = lower(v.nome));

-- Prazos: nascimento, admissão, fim do 1º período, fim da prorrogação, observação
update public.funcionarios f set
    nascimento = coalesce(v.nasc::date, f.nascimento),
    admissao = coalesce(v.adm::date, f.admissao),
    fim_experiencia1 = coalesce(v.p1::date, f.fim_experiencia1),
    fim_experiencia2 = coalesce(v.p2::date, f.fim_experiencia2),
    prazos_obs = coalesce(v.obs, f.prazos_obs)
  from public.clientes c, (values
    ('Clinica Simon Filial','Darllea do Socorro','1985-08-13',null,'2026-01-25','2026-03-11',null),
    ('Clinica Simon Filial','Rejane Santiago Casa Blanca','1979-07-20',null,null,null,null),
    ('Clinica Simon Filial','Giovanna','2000-04-24',null,'2026-04-10','2026-05-25',null),
    ('Clinica Simon Filial','Jussara Garcia Rodrigues',null,'2026-05-15','2026-06-27','2026-08-11',null),
    ('Clinica Simon Filial','Naiane',null,'2026-06-17','2026-07-31','2026-09-14',null),
    ('Clinica Viva Simon Matriz','Kauani Vitoria Correa Ferreira','2003-05-27',null,null,null,null),
    ('Clinica Viva Simon Matriz','Mayara Souza Gaspar Maciel',null,'2026-10-09','2026-11-22','2027-01-06','Iniciou dia 09/10/2026'),
    ('Clinica Viva Simon Matriz','Filipe Marcolla Davila Borba','2003-08-03',null,null,null,null),
    ('Clinica Viva Simon Matriz','Larissa de Brito','2006-01-02','2026-06-26','2026-08-09','2026-09-23',null),
    ('Clinica Viva Simon Matriz','Maria Eduarda Santos','1998-01-26','2026-02-27','2026-04-12','2026-05-27',null),
    ('Clinica Viva Simon Matriz','Nathalia Martins Criminacio','2006-07-09',null,'2026-04-22','2026-06-06',null),
    ('Clinica Viva Simon Matriz','Vitória da Silva Rodrigues',null,null,'2026-09-04','2026-10-19','Será desligada'),
    ('Clinica Viva Simon Matriz','Giseli Alves Do Prado','1984-06-01',null,null,null,null),
    ('Clinica Viva Simon Matriz','Rosangela Fabiano Da Silva','1975-01-23',null,null,null,null),
    ('Clinica Viva Simon Matriz','Camilla Taynara De Lima Dias','1995-04-01',null,null,null,null),
    ('Clinica Viva Simon Matriz','Alice de Souza Gonçalves','2003-07-02',null,'2026-09-05','2026-10-20','Enviado aviso de demissão a Camilla'),
    ('Clinica Viva Simon Matriz','Bruna Batista da Silva','2001-09-09','2026-09-15','2026-10-29','2026-12-13',null),
    ('Clinica Viva Simon Matriz','Elaine Claudino dos Santos','1982-03-08',null,'2026-01-23','2026-03-09',null),
    ('Clinica Viva Simon Matriz','Janaina Rodrigues','1989-11-14','2026-07-06','2026-08-19','2026-10-03','Pediu demissão 19/10/2026'),
    ('Clinica Viva Simon Matriz','Janaina Souza','1987-12-30','2026-07-16','2026-08-29','2026-10-13',null),
    -- na planilha a prorrogação estava com o ano 2026; corrigido para 2027 (admissão + 89 dias)
    ('Clinica Viva Simon Matriz','Ricaele Moreira dos Anjos','2005-12-30','2026-10-13','2026-10-27','2027-01-10','Iniciou dia 13/10/2026'),
    ('Clinica Viva Simon Matriz','Pedro Vitor','1997-08-22','2026-04-22','2026-06-05','2026-07-20',null),
    ('Clinica Viva Simon Matriz','Debora Santos da Rosa',null,'2026-09-25','2026-10-14','2026-12-23','Enviado prorrogação p/ Duda'),
    ('Clinica Viva Simon Matriz','Emanuella Valdevina Vieira','1996-11-09',null,null,null,null),
    ('Clinica Viva Simon Matriz','Cintia Roberta Amorim de Souza Ferreira','1986-03-31','2026-09-09','2026-10-23','2026-12-07','Enviado prorrogação para Debora'),
    ('Clinica Viva Simon Matriz','Daniela Urbano','1984-03-21','2026-03-11','2026-04-24','2026-06-08',null),
    ('Clinica Viva Simon Matriz','Tatyana Dias Franca','1988-05-12',null,null,null,null),
    ('Clinica Viva Simon Matriz','Daniel Moreira de Almeida','1984-05-01','2026-10-09','2026-10-23','2027-01-06','Iniciou dia 07/10/2026'),
    ('Clinica Viva Simon Matriz','Nataniel Souza de Avila','1981-10-07','2026-10-15','2026-11-28','2027-01-12','Iniciou dia 14/10/2026'),
    ('Clinica Viva Simon Matriz','Maria Eduarda Francisco Martins','2002-11-10','2026-09-23','2026-11-06','2026-12-21','Iniciou 19/09/2026')
  ) as v(empresa,nome,nasc,adm,p1,p2,obs)
 where c.id = f.cliente_id and c.nome = v.empresa and f.nome = v.nome;

-- Benefícios (abas Viva Filial e Viva Matriz): VA por mês, VT por dia (ida + volta) e empresa de ônibus
update public.funcionarios f set va_valor = v.va, vt_valor_dia = v.vt, vt_empresa = v.emp
  from public.clientes c, (values
    ('Clinica Simon Filial','Naiane',100::numeric,20.2::numeric,'Jotur Transportes'),
    ('Clinica Simon Filial','Giovanna',500,null,'Estrela (não quer receber VT por enquanto)'),
    ('Clinica Simon Filial','Jussara Garcia Rodrigues',350,13.8,'Biguaçu'),
    ('Clinica Simon Filial','Rejane Santiago Casa Blanca',500,20.2,'Jotur Transportes'),
    ('Clinica Simon Filial','Darllea do Socorro',100,null,null),
    ('Clinica Viva Simon Matriz','Camilla Taynara De Lima Dias',500,20.2,'Estrela Transportes'),
    ('Clinica Viva Simon Matriz','Cintia Roberta Amorim de Souza Ferreira',100,15.4,'Fenix'),
    ('Clinica Viva Simon Matriz','Daniel Moreira de Almeida',100,null,null),
    ('Clinica Viva Simon Matriz','Daniela Urbano',100,20.2,'Jotur Transportes'),
    ('Clinica Viva Simon Matriz','Debora Santos da Rosa',100,null,'Biguaçu (não quer receber VT por enquanto)'),
    ('Clinica Viva Simon Matriz','Elaine Claudino dos Santos',500,20.46,'Jotur Transportes'),
    ('Clinica Viva Simon Matriz','Emanuella Valdevina Vieira',800,null,null),
    ('Clinica Viva Simon Matriz','Filipe Marcolla Davila Borba',500,null,null),
    ('Clinica Viva Simon Matriz','Giseli Alves Do Prado',200,null,null),
    ('Clinica Viva Simon Matriz','Janaina Souza',100,14.48,'Estrela Transportes'),
    ('Clinica Viva Simon Matriz','Kauani Vitoria Correa Ferreira',500,20.2,'Jotur Transportes'),
    ('Clinica Viva Simon Matriz','Larissa de Brito',100,null,null),
    ('Clinica Viva Simon Matriz','Maria Eduarda Francisco Martins',100,21,'Jotur Transportes'),
    ('Clinica Viva Simon Matriz','Maria Eduarda Santos',500,null,null),
    ('Clinica Viva Simon Matriz','Mayara Souza Gaspar Maciel',100,null,null),
    ('Clinica Viva Simon Matriz','Nataniel Souza de Avila',100,15.5,'Biguaçu'),
    ('Clinica Viva Simon Matriz','Nathalia Martins Criminacio',500,14.4,'Fenix'),
    ('Clinica Viva Simon Matriz','Pedro Vitor',null,14.4,'Fenix'),
    ('Clinica Viva Simon Matriz','Ricaele Moreira dos Anjos',100,15,'Estrela Transportes'),
    ('Clinica Viva Simon Matriz','Rosangela Fabiano Da Silva',350,null,null),
    ('Clinica Viva Simon Matriz','Tatyana Dias Franca',100,null,null)
  ) as v(empresa,nome,va,vt,emp)
 where c.id = f.cliente_id and c.nome = v.empresa and f.nome = v.nome;

-- WhatsApp (aba Contatos), só de quem está cadastrado
update public.funcionarios f set telefone = v.tel
  from public.clientes c, (values
    ('Clinica Simon Filial','Darllea do Socorro','+55 48 8878-8453'),
    ('Clinica Simon Filial','Jussara Garcia Rodrigues','+55 48 99862-9042'),
    ('Clinica Viva Simon Matriz','Camilla Taynara De Lima Dias','+55 48 9165-7766'),
    ('Clinica Viva Simon Matriz','Daniela Urbano','+55 49 9915-2116'),
    ('Clinica Viva Simon Matriz','Elaine Claudino dos Santos','+55 48 9805-7057'),
    ('Clinica Viva Simon Matriz','Emanuella Valdevina Vieira','+55 48 9866-7136'),
    ('Clinica Viva Simon Matriz','Filipe Marcolla Davila Borba','+55 48 9180-8029'),
    ('Clinica Viva Simon Matriz','Giseli Alves Do Prado','+55 48 9992-7077'),
    ('Clinica Viva Simon Matriz','Kauani Vitoria Correa Ferreira','+55 48 9169-7904'),
    ('Clinica Viva Simon Matriz','Maria Eduarda Santos','+55 48 8880-2685'),
    ('Clinica Viva Simon Matriz','Nathalia Martins Criminacio','+55 48 9920-8544'),
    ('Clinica Viva Simon Matriz','Pedro Vitor','+55 92 8421-5587'),
    ('Clinica Viva Simon Matriz','Rosangela Fabiano Da Silva','+55 48 8849-8008'),
    ('Clinica Viva Simon Matriz','Tatyana Dias Franca','+55 48 8494-4528')
  ) as v(empresa,nome,tel)
 where c.id = f.cliente_id and c.nome = v.empresa and f.nome = v.nome and f.telefone is null;

notify pgrst, 'reload schema';

select c.nome as empresa, count(*) as colaboradores,
       count(f.fim_experiencia2) filter (where f.fim_experiencia2 >= current_date and f.situacao <> 'Desligado') as em_experiencia
  from public.funcionarios f join public.clientes c on c.id = f.cliente_id
 where c.nome like 'Clinica%' group by c.nome;
