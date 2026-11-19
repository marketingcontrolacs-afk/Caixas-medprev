# Estado do projeto: diário de passagem entre contas

Cada sessão acrescenta uma linha no topo: **data · conta · o que mudou · o que ficou pendente**.

- **19/11/2026 10:30 · conta 1 (thread "Importar e gerar contratos de clientes") · branch `claude/project-thread-yylf97` (NÃO publicado, aguarda OK da Carol)**
  - **Feito:** Gestão Controlacs › Clientes/Contratos/Documentos: **📄 Importar contrato** (lê PDF/Word e grava cliente, contrato, arquivo e modelo), **📝 Modelos de contrato** (modelo padrão melhorado + editor) e, dentro do contrato, **📝 Gerar contrato pelo modelo** (PDF + envio à Autentique). Detalhes em `docs/contratos/README.md`. Manual e Novidades atualizados.
  - Mudanças pequenas em código existente: `ctMostra` tira a classe `ktLargo`; `ctAbreAss(c,pre)` aceita documento e signatários já escolhidos (sem `pre` funciona como antes, mas sugere o representante salvo do cliente); `fcSyncCtl` liga a empresa nova ao cliente criado pela importação (`FC.ligaCtl`) em vez de criar outro.
  - **Banco:** v162 = tabela `ctl_modelos_contrato` (o MCP não deixou criar tabela; a Carol roda no SQL Editor). Próximo SQL livre: **v163**.
  - **Testado:** no navegador com o Supabase simulado e o contrato real da Viva (leitura, gravar, desfazer, gerar PDF, abrir a Autentique). **Pendente:** Carol rodar a v162, conferir o modelo e dar OK para publicar; teste real com a Autentique.

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
