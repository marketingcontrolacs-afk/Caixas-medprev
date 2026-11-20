# Estado do projeto: diário de passagem entre contas

Cada sessão acrescenta uma linha no topo: **data · conta · o que mudou · o que ficou pendente**.

- **19/11/2026 23:55 · conta 2 · `feat/chamados-editar-mensagem`:** quem escreveu pode **editar** a própria mensagem na conversa da tarefa. Fica marcada como "editada". Banco: migration `tarefa_comentarios_editar` (coluna `editado_em` e política `op_editar`, só o autor e nunca mensagem do sistema).

- **19/11/2026 23:45 · conta 2 · branch `feat/conciliacao-transf-extratos`**
  - **Conciliação:** com os extratos das duas contas importados e nada lançado, a linha ganha a sugestão "Transferência de/para <conta>? No extrato dela há…" (`GC.outrasL`, `k:'transfofx'`).
  - **Regra:** valor igual, sinal contrário, até 3 dias, mesma empresa.
  - **Ao aprovar:** cria os dois lançamentos (um em cada conta), já conciliados e ligados pelo mesmo `transf_id`.

- **19/11/2026 23:30 · conta 2 · branch `feat/chamados`**
  - **"Chamados":** junta as Tarefas e recados e as Solicitações num quadro só (`viewTar`), com 5 colunas: Nova › A fazer › Em andamento › Aguardando cliente › Concluída.
  - **Banco:** migration `tarefas_status_nova`; `tarefas.status` aceita 'nova'. O recado criado pelo cliente começa em "Nova".
  - **Solicitações no quadro:**
    - As solicitações aparecem como cartões "📨 #nº" (`chSolCarrega`, `chSolCard`, `chSolCol`).
    - Mapeamento: aberta sem responsável → Nova; aberta com responsável → A fazer; em_andamento → Em andamento; aguardando_cliente → Aguardando cliente; concluida/cancelada → Concluída.
    - Arrastar muda a situação. "A fazer" assume quem arrastou como responsável.
    - Clicar abre a solicitação. O "← Voltar aos Chamados" volta ao quadro (`SOL.deCh`).
    - "+ Novo chamado" abre a nova solicitação (lista de serviços). "+ Tarefa interna", para o escritório, abre a tarefa.
  - **Menu:** "Tarefas e recados" passou a se chamar "Chamados", e o item "Solicitações" saiu do menu. A tela `solic` continua existindo para abrir a solicitação.
  - **Pendente:** a conversa da tarefa (`tarefa_comentarios`) e a da solicitação (`sol_mensagens`) continuam em tabelas separadas, cada uma com o seu histórico. Se quiser tudo numa tabela só, é uma migração maior.

- **19/11/2026 23:00 · conta 2 · branch `feat/conciliacao-tarefa-por-linha`**
  - **Gerar tarefa (conciliação):** agora cria **uma tarefa por linha do banco**, com o título "Identificar: dd/mm · quem · valor". A observação vira a 1ª mensagem (interna) da conversa, e o item fica em `tarefa_lancamentos.ofx_id`.
    - A tarefa antiga que juntava duas linhas foi dividida em duas e arquivada.
  - **Alerta "⚠ Pago para outra pessoa?"** (`gcOutraPessoa`): nas saídas, compara o nome de quem recebeu, no extrato, com o `pessoa_nome` do lançamento. Se não houver nenhuma palavra em comum (fora as genéricas), mostra o alerta. Caso: Fabio Franzoni × Luciane Gava.
  - **Banco:**
    - Juntados 26 cadastros duplicados "… - Mpa" com o cadastro de mesmo nome (cópia dos apagados em `fin_pessoas_mescladas`, migration `fin_pessoas_mescladas_backup`).
    - Ficaram separados, de propósito, 2 pares com CNPJ/CPF diferente: Clínica Santa Bárbara (filial) e Derma Clinn.
    - O cadastro do Fabio Franzoni ficou sem chave Pix: a chave 46999720024 era da Luciane.

- **19/11/2026 22:25 · conta 2 · `fix/conciliacao-tarefa-prioridade`:** "Gerar tarefa" dava erro porque a prioridade 'media' não existe. Os valores aceitos em `tarefas.prioridade` são baixa, normal, alta e urgente. Corrigido para 'normal'.

- **19/11/2026 22:20 · conta 2 · branch `fix/conciliacao-transferencia-entre-contas`**
  - **Conciliação:** reconhece transferência entre contas da empresa (`GC.outras`, sugestão `k:'transf'`), e o Ligar mostra lançamentos de outras contas, com os de valor igual primeiro.
  - **Novo `docs/financeiro/REGRAS.md`:** reúne as regras e os casos reais do financeiro (conciliação, remessa, repasse, rotina). **Leia antes de mexer nessas telas.**

- **19/11/2026 22:20 · conta 2 · branch `feat/conciliacao-gerar-tarefa`**
  - **Banco:** migration `tarefa_lancamentos_ofx_id`, nova coluna `tarefa_lancamentos.ofx_id` (FK para `fin_ofx`, `on delete set null`).
  - **Conciliação bancária:** selecione linhas e use **📋 Gerar tarefa** (`gcTarefa`, só para o escritório).
    - As linhas entram na tarefa "Conciliação: lançamentos do banco a identificar" da empresa. É uma tarefa aberta por empresa: se já existir, as linhas entram nela.
    - Cada item leva data, conta, histórico, valor e a observação.
    - A linha mostra "📋 Em tarefa" até o item ser validado ou a tarefa concluída.

- **19/11/2026 22:10 · conta 2 · branch `feat/conciliacao-ligar-varios`**
  - Conciliação bancária: cada linha do banco ganhou o botão **Ligar** (diálogo `dlgGCL`, funções `gclAbre`, `gclDesenha` e outras).
    - Mostra os lançamentos do sistema ainda não conciliados (mesmo tipo, até 15 dias; ou 60 com "datas mais distantes") e as contas em aberto, com caixa de seleção, busca e total.
    - Quando a soma bate com a linha, concilia como a remessa (`k:'rem'`, `ofx_soma`) e dá baixa nas contas.
  - No caminho `rem` do `gcAprovar`, a conta a receber agora entra com o valor positivo.
  - **Pendente:** várias linhas do banco para um lançamento já existente (o contrário) ainda não dá. Hoje existe só o "Lançar juntas", que cria um lançamento novo.

- **19/11/2026 22:00 · conta 2 · branch `fix/conciliacao-linha-somada`**
  - **Problema:** na conciliação bancária, quando o extrato soma vários Pix do mesmo dia com o mesmo histórico numa linha só (`fin_ofx.qtd > 1`, `itens` com os valores), a linha aparecia "Sem lançamento", mesmo com cada Pix já lançado ou pago no Contas a pagar. Isso abria o risco de lançar de novo. Caso: Platano em 05/11, MPA PB, 4 Pix somando R$ 7.317,44.
  - **Correção:** novo `gcSomaDe`: cada valor de `itens` procura um lançamento ainda não conciliado (mesmo valor, até 3 dias) ou uma conta em aberto (até 10 dias).
    - Se todos baterem, vira sugestão do tipo `rem`: ao aprovar, liga os lançamentos com `ofx_soma` e dá baixa nas contas.

- **19/11/2026 21:10 · conta 2 · branch `feat/repasse-busca-todas-colunas`**
  - Parceiros MP › Repasse: a busca procura em **todas as colunas** (`rnBuscaTudo`): parceiro, CPF/CNPJ, guias, valor, valor da NF, nota fiscal, conta e Pix, Pagar em, situação e protocolo.
  - O valor pode ser digitado como 17020, 17.020 ou 17.020,00.

- **19/11/2026 20:55 · conta 2 · branch `feat/conciliacao-total-selecao`**
  - Conciliação bancária: a barra "N linhas selecionadas" agora mostra o **total** das linhas marcadas. Se forem só saídas ou só entradas, mostra o total delas; se forem as duas, mostra o saldo, com entradas e saídas separadas.

- **19/11/2026 20:35 · conta 2 · branch `fix/remessa-regra-sequencial`**
  - **Regra da numeração da remessa (Sicredi):** o banco espera o número seguinte ao último arquivo que ele **aceitou**; arquivo recusado não conta.
    - Quando a recusa é por **"Sequencial fora de ordem"**, NÃO se libera o número (responder "Cancelar" na 2ª pergunta) e se acerta o "Nº da última remessa" da conta.
    - A pergunta do cancelamento e o manual agora explicam isso.
  - **Caso MPA Pato Branco (Sicredi, convênio 78D7):** nenhum arquivo tinha sido aceito.
    - Os nº 1 a 4 foram liberados (nsa negativo e `/C` no seu número), e `cnab_seq` voltou para 0.
    - O arquivo seguinte, nº 1, foi aceito em 19/11.

- **19/11/2026 19:35 · conta 2 · banco: migration `fin_contas_ligar_tes_so_quando_muda`**
  - **Problema:** salvar uma conta bancária (por exemplo, a Sicredi da MP Coronel) dava "canceling statement due to statement timeout".
  - **Causa:** o trigger `fin_contas_ligar_tes` rodava `tes_ligar_banco` (a empresa inteira) em todo update que citasse nome, conta_bc, tipo ou ativo, mesmo sem mudar nada. O front sempre manda esses campos.
  - **Correção:** o trigger foi dividido em dois:
    - `fin_contas_ligar_tes`, só no insert;
    - `fin_contas_ligar_tes_upd`, no update, com `WHEN` (só quando algum desses quatro campos muda de verdade).
  - Não houve mudança no `index.html`.
  - **Pendente:** se trocar o nome, o tipo, o "ativo" ou o nome no Bom Controle numa empresa grande, ainda pode estourar o tempo. Nesse caso, otimizar o `tes_ligar_banco`.

- **19/11/2026 16:05 · conta 1 (thread "Anexar boleto no pagamento de parceiros") · publicado (OK da Carol)**
  - **Boleto só guardado no repasse** (Carol, 19/11: anexar não pode mandar sozinho para a remessa; às vezes ela paga à mão). No repasse SEM conta a pagar, "📎 Anexar boleto"/"Colar linha" (`rnBolItem`) só lê a linha e guarda arquivos + linha em `repasse_itens.boleto` (**v165** RODADA); não cria conta a pagar. Chip "📎 Boleto guardado" com Ver e Tirar boleto (Desfazer). `rnCriaTitulos` (Pagar em / Gerar) cria a conta já como Boleto, com o valor do boleto (diferença na obs) e os anexos. Repasse que já tem conta a pagar continua anexando nela (`bolNoTitulo`).

- **19/11/2026 15:20 · conta 1 (thread "Anexar boleto no pagamento de parceiros") · branch `claude/project-thread-hna1z9` (ainda não publicado)**
  - Envio de remessa: aviso `#rmTir` acima da lista quando há pagamentos tirados da remessa (quantos, valor, nomes), com "↩ Trazer todos de volta para a remessa" (`rm_trazTodos`, com Desfazer) e "Ver quais são" (`rm_verTir`). Cancelar remessa (`rm_cancelar`) agora também tira o `sem_remessa` dos títulos dela. Sem SQL. **Pendente:** OK da Carol.

- **19/11/2026 14:30 · conta 1 (thread "Descontar guias da Top Imagem no repasse") · branch `claude/project-thread-h0h07i` (ainda não publicado)**
  - **Arquivo de desconto do parceiro** (Carol, 19/11; ex.: Top Image, relatório de atendimentos por representante = guias recebidas na clínica). Marca nova no cadastro do parceiro (só escritório): "Exige arquivo de desconto no repasse" (`parceiros.desc_arq`) + "Nome do desconto" (`desc_arq_nome`, ex.: Representante).
  - Repasse da semana: o repasse do parceiro marcado mostra "Falta o arquivo de desconto" com "📎 Anexar arquivo de desconto" (Excel/CSV/PDF) ou "Não tem desconto" (`repasse_itens.desc_arq`). Leitura `daLeArquivo`/`daLeLinhas` (aguenta colunas desalinhadas do Crystal), conferência `rnDAAnexa` (guias já descontadas antes ficam desmarcadas, empresa obrigatória), lançamento `rnDALanca` (um `repasse_descontos` com motivo "<nome> do período X a Y (N guias)"; se já há conta a pagar em aberto, sai na hora por `descNaConta`; o arquivo vai para os anexos da conta a pagar). Desfazer `rnDADesfaz`. Quadro e filtro "Falta arquivo de desconto". Trava em "Gerar remessa" e "Marcar como pago" (`rnDATrava`).
  - **Contas a pagar:** todo desconto de parceiro (manual ou por arquivo) agora também entra na **descrição** da conta a pagar: " · Descontado R$ X ref. <motivo>" (`descDescr`, em `rnCriaTitulos` e `descNaConta`). A observação continua como antes.
  - Não mexe no boleto do repasse (regra do Santa Luzia): são coisas separadas.
  - Banco: **v164** RODADA pelo MCP (colunas acima; cadastro do parceiro Top Image com a marca, ligado ao fornecedor de mesmo CNPJ; desconto de R$ 1.560,00 em Oliveira SJ, período 01/11 a 15/11/2026, 6 guias, para o repasse de 19/11). SQL e DESFAZER em `sistema-caixa/sql-versoes`. **Próximo SQL livre: v165.**
  - Testado no simulador (prints em `sistema-caixa/desconto-arquivo/`). **Pendente:** OK da Carol para publicar.

- **19/11/2026 12:55 · conta 1 (thread "Anexar boleto no pagamento de parceiros") · branch `claude/project-thread-hna1z9` (ainda não publicado)**
  - **Só aceita TED (nunca Pix)** (Carol, 19/11): o Inter mandou como Pix a TED da Clínica Viva Simon (o arquivo estava certo, lote TED; o Inter faz transferência para outro banco pelo Pix por agência e conta). Marca nova no cadastro do fornecedor (Gestão financeira › Cadastros, `gf_so_ted`) e do parceiro (`pc_so_ted`, só escritório). `rmForma` nunca usa Pix para quem tem a marca (`soTedDe`: fornecedor ou parceiro ligado); no Envio de remessa do Inter a linha fica de fora com o aviso para pagar à mão; Sicredi e Santander vão por TED no arquivo.
  - Banco: **v163** RODADA (colunas `so_ted` em `fin_pessoas` e `parceiros`, padrão false); Clínica Viva Simon Fpolis e Kobrasol já marcadas (parceiros e fornecedores ligados). SQL em `sistema-caixa/sql-versoes`. **Pendente:** OK da Carol para publicar.

- **19/11/2026 11:50 · conta 1 (thread "Anexar boleto no pagamento de parceiros") · branch `claude/project-thread-hna1z9` (ainda não publicado)**
  - Envio de remessa, ações em lote abaixo da lista (`rmLoteBar`): "↩ Voltar ao repasse os sem dados de pagamento", "↩ Voltar ao repasse os marcados", "Tirar da remessa os sem dados de pagamento" (contas que não são de repasse) e "Tirar da remessa os marcados". Funções `rmVoltaLote` e `rmTiraLote`, com Desfazer (o voltar recria as mesmas contas a pagar com o mesmo id, religa repasses, descontos e o status do relatório). O "Voltar ao repasse" da linha passou a usar o mesmo caminho, então também tem Desfazer. Sem SQL.

- **19/11/2026 11:30 · conta 1 (thread "Anexar boleto no pagamento de parceiros") · branch `claude/project-thread-hna1z9` (ainda não publicado)**
  - Leitura de boleto (`leArquivoDoc`, vale para todas as telas que leem documentos): PDF com texto mas com os números desenhados como imagem (boleto Bradesco do Santa Luzia/DASA, "Microsoft Print to PDF") não achava a linha digitável. Agora, se o texto tem os rótulos de boleto (ficha de compensação, nosso número, beneficiário…) e nenhuma linha, também lê por OCR e junta com o texto. Testado com o arquivo real: R$ 1.553,13, venc. 19/11/2026. Sem SQL.

- **19/11/2026 09:45 · conta 1 (thread "Anexar boleto no pagamento de parceiros") · branch `claude/project-thread-hna1z9` (ainda não publicado)**
  - O boleto do repasse (publicado às 09:30, portal #119) agora aceita **vários arquivos de uma vez** (boleto e NF, também XML). O arquivo com a linha digitável vira o boleto; os outros vão para os anexos como "Nota fiscal" (ou "Outros"). O XML só é lido.
  - O botão aparece também no repasse **sem empresa**: abre "Qual empresa vai pagar?", cria a conta a pagar (o mesmo que "Pagar em", `rnPagarEm`) e anexa. No Envio de remessa também vale para vários arquivos.
  - **Vale o valor do boleto** (Carol, 10:49): ao anexar, a conta a pagar passa a ter o valor do boleto (retenção de impostos ou diferença), com a diferença anotada na observação; no repasse aparece o valor do relatório riscado e "− R$ X pelo boleto". Se a conta já tem pagamento, o valor não muda. O Desfazer volta o valor antigo.
  - Sem SQL. **Pendente:** OK da Carol para publicar.

- **19/11/2026 09:40 · conta 1 (thread "Anexar boleto no pagamento de parceiros") · branch `claude/project-thread-hna1z9` (ainda não publicado)**
  - **Boleto no pagamento, opcional** (Carol: "só tem 2 casos", ex.: Laboratório Médico Santa Luzia SC). Nada ficou obrigatório; quem não anexa continua por Pix ou conta.
    - Parceiros MP › Repasse da semana: na coluna Situação de cada repasse com conta a pagar em aberto, "📎 Anexar boleto" ou "Colar linha". Com boleto, aparece "📎 Vai por boleto" e o botão "Tirar boleto".
    - Gestão financeira › Envio de remessa (qualquer conta a pagar, de qualquer empresa, que iria por Pix/TED ou que estava sem forma): os mesmos dois botões. A linha do boleto mostra vencimento e valor.
    - Funções novas: `bolNoTitulo` (lê o arquivo com `leArquivoDoc`, usa a linha corrigida do portal #111, recusa linha que não confere com `bolConfere`, avisa valor diferente e boleto repetido, guarda o arquivo em `documentos` como "Boleto ou fatura" e grava `fin_titulos.linha_digitavel` + `forma='Boleto'`) e `bolTiraTitulo`. Tudo com ↶ Desfazer.
    - Santander: o boleto de parceiro sem CPF/CNPJ no fornecedor usa o CPF/CNPJ do cadastro do parceiro (`rmDoc`).
  - Sem SQL. Testado no simulador (prints em `sistema-caixa/boleto-parceiros/`). **Pendente:** OK da Carol para publicar; testar com um boleto real.

- **19/11/2026 09:00 · conta 2 · branch `feat/cadastrar-fornecedor-rotina`**
  - **Rotina diária, modo escritório:** em Boletos e notas a pagar, Cartão de crédito e Tesouraria, o campo do fornecedor ganhou o botão **+ Cadastrar** (o mesmo `data-pesnova`/`PESNOVA` da Gestão financeira). O cadastro usa a empresa do lançamento (`regCli()`).
  - **Leitura do documento anexado:** antes era só em Boletos e notas a pagar. Agora também vale no Cartão de crédito, na Tesouraria e nas saídas do fechamento de caixa.
    - Preenche o que estiver em branco: valor, nº da nota e fornecedor.
    - O fornecedor sai de qualquer CNPJ do documento que não seja o da empresa: primeiro procura no cadastro (inclusive pela raiz do CNPJ), depois em `fornecedor_por_documento`.
    - Se o fornecedor não estiver cadastrado, fica o nome lido do documento e o "+ Cadastrar" já abre com o CNPJ.
  - Sem SQL. **Teste:** só a checagem de sintaxe; o simulador de testes não tem os módulos da Rotina diária. Conferir com um documento real.

- **19/11/2026 08:40 · conta 2 · branch `fix/salvar-sem-fornecedor`**
  - **Feito:** dá para salvar sem fornecedor cadastrado.
    - Em Boletos e notas a pagar e em Cartão de crédito, o campo Fornecedor ficou opcional.
    - Na conferência de Exportação Bom Controle (caixa, tesouraria, boletos e notas, cartão), o "Fornecedor no Bom Controle" pode ficar em branco. O lançamento fica com `fornecedor_bc = '-'` (constante `FBC_SEM`) e vai para a exportação só com o nome digitado, sem CNPJ.
    - Se digitar um nome que não está na lista, continua pedindo para escolher da lista ou apagar.
  - Sem SQL. O fechamento de caixa não tem campo de fornecedor e não mudou.

- **19/11/2026 00:00 · conta 1 (thread "Revisar tudo o que já foi feito") · branch `claude/project-thread-vp02g6`**
  - **Publicado** pela Cloudflare Pages, com OK da Carol (19/11): envio de NFS-e por e-mail em lote (branch `claude/project-thread-xk2hx8`, descrito abaixo). Sem SQL.
  - Revisão geral: os branches antigos `claude/project-thread-*` já estão na `main` (o conteúdo foi publicado em outras PRs); não há outra coisa aprovada esperando publicação.
  - **Pendente (Carol):** NF automática dos contratos + boleto Inter (aguardar); v161 (acessos `solicitacoes`/`gestor`) não rodada; apagar o projeto do ERP no Netlify depois de confirmar o domínio *Active* na Cloudflare; testar um envio real de NFS-e por e-mail.

- **18/11/2026 22:45 · conta 1 (thread "Enviar notas fiscais por e-mail em lote") · branch `claude/project-thread-xk2hx8`**
  - **Feito:** envio de várias NFS-e por e-mail de uma vez. É um motor genérico (`NSL`) no `index.html`: `nslTh`/`nslTd`/`nslBotao`/`nslPoda` e o diálogo `dlgNSL`.
    - Fica em Controlacs › Notas fiscais, em Parceiros MP › Notas fiscais emitidas e no fim da emissão em lote dos parceiros.
    - Antes de enviar, abre uma conferência com o e-mail de cada tomador.
    - Cada nota sai num e-mail só dela, pela função `nfse-email`, que registra o envio em `nfse_notas.extra.emails`.
    - Sem SQL, e a função `nfse-email` não mudou. Manual e Novidades atualizados.
  - **Testado:** no navegador, com o Supabase e a função simulados. **Pendente:** nenhum e-mail real foi enviado ainda; testar com notas de verdade depois da publicação. Publicação aprovada pela Carol; **publicado em 19/11/2026** (ver linha acima).

- **18/11/2026 23:35 · conta 2 · hospedagem migrada para a Cloudflare Pages**
  - O site agora sai da **Cloudflare Pages** (projeto `portal-controlacs`). O DNS `erpfinanceiro` aponta para `portal-controlacs.pages.dev`.
  - No Netlify, os builds do `erpfinanceiro.controlacs.com.br` foram **parados**. Não reativar. O `controlacs.com.br` (site institucional) continua no Netlify.
  - Merge de `feat/solicitacoes-servicos` na `main` dos dois repositórios.
  - **Pendente:** confirmar que o domínio aparece como *Active* na Cloudflare; depois, apagar o projeto do ERP no Netlify.

- **18/11/2026 22:15 · conta 2 · branch `feat/solicitacoes-servicos` (ainda não publicado)**
  - **No banco (já aplicado):**
    - 22 serviços de RH em `sol_tipos`, incluindo advertência, suspensão, atestado, INSS/CAT e "Descontos em folha" (até o dia 20).
    - "Alteração na folha" virou "Lançamentos na folha".
  - **No branch:**
    - A "Nova solicitação" virou uma lista para escolher (agrupada por área) e mostra só os serviços do contrato da empresa: `clientes.bpo_rh` / `bpo_financeiro`; "Outros" sempre aparece.
    - Mostra a descrição do serviço e avisa quando passou do dia 20 nos descontos.
  - **Também no branch:** Configurações › **Serviços das solicitações** (só a Master, `VIEW 'solserv'`). Ali se incluem, editam e desativam os serviços por área, com prazo em dias, documentos pedidos, orientação e ordem.
  - **Publicado em 18/11/2026 23:35** pela Cloudflare Pages.

- **18/11/2026 21:45 · conta 2 (chat Solicitações) · branch `feat/solicitacoes-modulo`**
  - **Feito:** módulo **Solicitações** dentro do `index.html`. Menu: Comunicação › Solicitações (`VIEW 'solic'`, em `SEMPRE`). Código num bloco só (`// ===== SOLICITAÇÕES + ADMISSÃO`), antes do `openView`; HTML na `section#viewSol`; CSS com prefixo `.sol-`. Também entra a página `admissao.html`.
    - Lista com filtros e selo de novidade; contador no menu, pelas `sol_notificacoes`.
    - Nova solicitação. A admissão tem 6 campos: nome, WhatsApp, cargo, horário, início e experiência, com os vencimentos calculados.
    - Detalhe: conversa com nota interna e tempo real; arquivos; histórico; ações da equipe (assumir, status, prioridade).
    - Painel de admissão:
      - etapas 1–7, com avançar;
      - setor e salário;
      - gerar link e abrir o WhatsApp;
      - pedir correção;
      - enviar ao colaborador (guia da Corpori preenchida via pdf-lib, carta, aviso do contrato);
      - ficha em PDF (impressão) e Excel.
  - **Testado:** no navegador, com o Supabase simulado. **Não testado:** com o banco real; e a geração da guia, porque o pdf-lib não carrega offline.
  - **Pendente:** testar com o banco real depois do merge; cadastrar as aptidões por cargo; definir o envio da ficha por e-mail à contabilidade.

- **18/11/2026 21:20 · conta 2 (chat Solicitações) · branch `feat/solicitacoes-admissao`**
  - **Feito:** criada a página pública `admissao.html` (formulário do novo colaborador em 5 passos, envio de documentos, acompanhamento com download e devolução). Testada no navegador com o backend simulado. Ainda falta o teste com o banco real, que precisa de um link gerado pela equipe.
  - **Pendente:** as telas do módulo Solicitações dentro do `index.html`, que é onde a equipe gera o link e o cliente abre os pedidos. Ainda não comecei; quem pegar, siga `docs/solicitacoes/INSTRUCOES.md`, seções 3, 5 e 6.

- **18/11/2026 21:00 · conta 2 (chat Solicitações)**
  - **Feito:** criados `CLAUDE.md`, `docs/` e `modelos/guia_corpori.pdf`. Banco do módulo Solicitações + Admissão aplicado (ver `docs/solicitacoes/BANCO.md`).
  - **Em andamento:** telas do módulo Solicitações dentro do `index.html` e a página pública de admissão do colaborador (`admissao.html`), pela conta 2.
  - **Pendente:**
    - Cadastrar as aptidões da guia do ASO por cargo. Até agora só existe "Auxiliar de cozinha → Manipulação de Alimentos".
    - Definir o e-mail da contabilidade para o envio da ficha.
