# Portal do Cliente Controlacs (ERP): contexto compartilhado

Este arquivo é lido pelo Claude em **qualquer conta** que abrir este repositório. Conversas e memória não passam de uma conta para a outra, por isso **tudo o que for decidido precisa ficar escrito aqui ou em `docs/`**.

## O que é
- Portal do Cliente / ERP da **Controlacs** (BPO financeiro e RH). No ar em `erpfinanceiro.controlacs.com.br` (Netlify; também há uma cópia em GitHub Pages).
- Site estático: **um único `index.html`** (HTML, CSS e JS puro, tudo dentro de um IIFE), com `supabase-js` via CDN. Não há etapa de build.
- Banco: Supabase, projeto **Caixas MedPrev** (`qlopcclhswtbgrupfhyy`). O front usa só a chave **publishable**. Nunca coloque a `service_role` ou outros segredos no código.
- Os repositórios `caixas-medprev` e `portal-controlacs` publicam o **mesmo** `index.html`.

## Regras do repositório (ele é público)
- **Nunca** versionar SQL, planilhas, CSV ou dados de clientes e colaboradores. O `.gitignore` já bloqueia `*.sql`. Os SQL ficam na pasta local do projeto (`sistema-caixa/sql-versoes`, `sistema-caixa/para-rodar`) e no histórico de migrations do Supabase.
- Mudanças em branch + PR. O merge na `main` publica o site.
- Comentários no código em português, com quem pediu e a data (padrão já usado: "Carol, 18/11").

## Trabalho em duas contas do Claude
1. **Antes de começar:** `git pull` e leia `docs/ESTADO.md`, que diz o que está em andamento e o que foi feito por último.
2. **Ao terminar:** acrescente uma linha em `docs/ESTADO.md` (data, conta, o que mudou, o que ficou pendente) no mesmo PR.
3. Evite que as duas contas mexam no `index.html` ao mesmo tempo. Se precisar, combine pelo `docs/ESTADO.md`.
4. Mudança no banco: aplique pelo Supabase (migration com nome descritivo) e registre em `docs/` o que mudou. **Não** versione o SQL.

## Módulos em construção
- **Solicitações + Admissão** (portal de chamados dos clientes, conversa, documentos, admissão com link para o novo colaborador, guia do ASO e ficha para a contabilidade).
  - **Especificação completa:** `docs/solicitacoes/INSTRUCOES.md`
  - **O que já está no banco:** `docs/solicitacoes/BANCO.md`
  - **Modelo da guia da clínica (Corpori):** `modelos/guia_corpori.pdf`
  - **Protótipo visual:** https://claude.ai/artifact/Aia94pC99NcAju6aaMTJ58
