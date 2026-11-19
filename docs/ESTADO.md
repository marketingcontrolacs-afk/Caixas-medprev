# Estado do projeto: diário de passagem entre contas

Cada sessão acrescenta uma linha no topo: **data · conta · o que mudou · o que ficou pendente**.

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
