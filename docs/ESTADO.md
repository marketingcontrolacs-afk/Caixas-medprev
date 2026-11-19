# Estado do projeto: diário de passagem entre contas

Cada sessão acrescenta uma linha no topo: **data · conta · o que mudou · o que ficou pendente**.

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
