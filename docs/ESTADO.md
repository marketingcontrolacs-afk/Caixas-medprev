# Estado do projeto: diário de passagem entre contas

Cada sessão acrescenta uma linha no topo: **data · conta · o que mudou · o que ficou pendente**.

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
