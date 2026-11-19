# Módulo Solicitações + Admissão — instruções de implementação no ERP Controlacs

Documento para quem vai programar as telas no ERP (erpfinanceiro.controlacs.com.br). O banco Supabase (**Caixas MedPrev**) já tem as tabelas, as regras de acesso (RLS) e as funções descritas aqui. **Não altere as tabelas existentes do ERP**: o módulo usa só as tabelas `sol_*`.

Protótipo navegável (visual e comportamento esperados): https://claude.ai/artifact/Aia94pC99NcAju6aaMTJ58

---

## 1. Quem é quem (usa os usuários do ERP)

| Papel | Como é identificado | O que pode |
|---|---|---|
| Equipe (escritório) | `perfis.papel = 'escritorio'` → `eh_escritorio()` | Vê e atende todas as solicitações, notas internas, muda status e etapas |
| Admin | `perfis.papel = 'escritorio' and admin` → `eh_admin()` | O mesmo da equipe, mais o cadastro de tipos, cargos e unidades da clínica e a exclusão de solicitações |
| Cliente — gestor | `perfis.papel = 'operador'`, `tipo = 'cliente'`, `cliente_id` | Abre e vê **todas** as solicitações da empresa dele |
| Cliente — colaborador | `perfis.papel = 'operador'`, `tipo = 'colaborador'` | Abre e vê **só as que ele mesmo abriu** |
| Acesso extra | `acessos (user_id, cliente_id, modulo = 'solicitacoes', nivel)` | Dá acesso a outra empresa; `nivel = 'gestor'` vê tudo dela |
| Novo colaborador | **Sem login**. Só um token no link | Preenche o formulário, envia documentos e baixa o que o RH mandar |

A RLS já filtra tudo: basta consultar normalmente com o cliente Supabase logado.

## 2. Tabelas

- `sol_tipos`: catálogo de serviços (`nome`, `categoria` financeiro|rh|fiscal|outro, `sla_horas`, `documentos` jsonb, `ativo`, `ordem`). A admissão é o tipo **"Admissão de colaborador"**.
- `sol_solicitacoes`: `numero` (protocolo, automático), `cliente_id`, `tipo_id`, `titulo`, `descricao`, `dados` jsonb, `status` (aberta | em_andamento | aguardando_cliente | concluida | cancelada), `prioridade` (baixa | normal | alta | urgente), `responsavel`, `responsavel_nome`, `criado_por`, `criado_por_nome`, `prazo` (calculado pelo SLA), `concluida_em`.
- `sol_mensagens`: conversa (`texto`, `interno` = nota só da equipe, `autor_nome`, `da_equipe`). Mensagem sem autor = mensagem do sistema.
- `sol_anexos`: arquivos (`caminho` no bucket **solicitacoes**, `nome`, `documento`, `interno`, `enviado_por_nome`).
- `sol_eventos`: linha do tempo (`tipo`, `de`, `para`, `autor_nome`).
- `sol_leituras`: última leitura por usuário (para o selo de "nova mensagem").
- `sol_notificacoes`: avisos por usuário (`titulo`, `texto`, `lida_em`).
- `sol_cargos`: `nome`, `documentos` extras (ex.: Coren), `pede_uniforme`, `aptidoes` (para a guia do ASO).
- `sol_clinica_unidades`: unidades da Corpori (`nome`, `endereco`, `whatsapp`, `campo_pdf`).
- `sol_admissoes`: uma por solicitação de admissão (`token`, `colaborador_nome`, `colaborador_whatsapp`, `cargo_id`, `cargo_nome`, `setor`, `salario`, `etapa` 1–7, `status` pendente | enviado | correcao | aprovado, `dados` jsonb do formulário, `expira_em`).
- `sol_admissao_envios`: o que o RH mandou ao colaborador (`titulo`, `instrucoes`, `caminho` ou null se for só aviso, `retorno_documento`, `retorno_anexo_id`).

Os campos de autor, número, prazo, nomes, histórico e notificações são preenchidos **pelo banco**. O front não envia esses campos.

## 3. Telas do portal (usuários logados)

Item novo no menu do topo: **Solicitações**, com contador vermelho = `sol_notificacoes` não lidas. Abas: **Solicitações** e **Nova solicitação** (esta só para clientes).

### 3.1 Lista
```js
supabase.from('sol_solicitacoes')
  .select('id, numero, titulo, status, prioridade, prazo, responsavel_nome, criado_em, atualizado_em, cliente_id, clientes(nome), sol_tipos(nome)')
  .order('atualizado_em', { ascending: false })
```
- **Filtros do cliente:** Todas · Precisam de você (`aguardando_cliente`) · Em andamento (`aberta`, `em_andamento`) · Concluídas.
- **Filtros da equipe:** Todas · Novas · Em andamento · Aguardando cliente · Concluídas. A equipe também vê o nome da empresa e tem filtro por empresa.
- **Selo "nova mensagem":** quando `atualizado_em > sol_leituras.lido_em` do usuário.

### 3.2 Nova solicitação (cliente)
1. Cartões com os `sol_tipos` ativos, mostrando o prazo.
2. Campos conforme o tipo escolhido:
   - **Tipo comum:** título e detalhes.
   - **Tipo "Admissão de colaborador":** só estes 6 campos, todos obrigatórios:
     - Nome do colaborador
     - WhatsApp do colaborador
     - Cargo (`select` de `sol_cargos` ativos)
     - Horário (texto livre, ex.: "07h às 19h (12x36)")
     - Data de início
     - Período de experiência: `45+45` | `30+60` | `15+75` | `90` | `sem`
   - Mostrar os vencimentos calculados: `rpc('sol_experiencia_vencimentos', { p_data_inicio, p_experiencia })` → `{primeiro, segundo}`.
3. Gravar:
```js
supabase.from('sol_solicitacoes').insert({
  cliente_id, tipo_id, titulo: 'Admissão de ' + nome, descricao: observacao || null,
  dados: { colaborador_nome, colaborador_whatsapp, cargo_id, horario, data_inicio /* AAAA-MM-DD */, experiencia }
}).select().single()
```

### 3.3 Detalhe da solicitação
- **Cabeçalho:** #número · tipo · empresa · título · aberta por · prazo · responsável · selo de status.
- **Ações da equipe:**
  - "Assumir": `update({ responsavel: auth.uid() })`.
  - Status: `update({ status })`.
  - Prioridade e prazo.
- **Ação do cliente:** cancelar, só enquanto `aberta`. Qualquer outra mudança feita pelo cliente o banco recusa.
- **Conversa:**
  - Envio: `insert sol_mensagens { solicitacao_id, texto, interno }`. A caixa "Nota interna (o cliente não vê)" aparece só para a equipe.
  - Notas internas em amarelo, mensagens do sistema centralizadas e em cinza.
  - Quando o cliente responde uma solicitação "aguardando cliente", o banco a volta para "em andamento".
- **Tempo real:** `supabase.channel(...).on('postgres_changes', { table: 'sol_mensagens', filter: 'solicitacao_id=eq.' + id }, ...)`. Faça o mesmo para `sol_notificacoes` (`user_id=eq.<eu>`).
- **Leitura:** ao abrir, `upsert sol_leituras { solicitacao_id, user_id, lido_em: now }`.
- **Anexos:**
  - Upload em `solicitacoes/{cliente_id}/{solicitacao_id}/{uuid}-{nome}`.
  - Depois do upload: `insert sol_anexos { solicitacao_id, caminho, nome, mime, tamanho, documento?, interno? }`.
  - Download: `storage.from('solicitacoes').createSignedUrl(caminho, 300)`.
- **Histórico:** `sol_eventos` em ordem decrescente.

### 3.4 Painéis extras quando o tipo é Admissão (`sol_admissoes` da solicitação)

**a) Andamento:** barra com 7 etapas, visível para gestor e equipe.
1. Solicitação recebida
2. Link enviado ao colaborador
3. Colaborador preenchendo
4. Conferência do RH
5. Exame admissional
6. Contrato e eSocial
7. Admissão concluída

As etapas 2–4 avançam sozinhas, pelo banco. Da 3 em diante, a equipe usa "Avançar para…": `rpc('sol_admissao_etapa', { p_solicitacao, p_etapa })`. A etapa 7 conclui a solicitação.

Mostrar também colaborador e WhatsApp, cargo, **setor**, horário, início, experiência e vencimentos.

**b) Setor e salário:** só a equipe preenche, com `update sol_admissoes set setor, salario`. O cliente não vê o salário.

**c) Link do colaborador (equipe):**
- "Gerar link": `rpc('sol_admissao_gerar_link', { p_solicitacao })` → `token`. Ele pega nome, WhatsApp e cargo do pedido do gestor.
- URL: `https://erpfinanceiro.controlacs.com.br/admissao.html?t={token}`.
- "Enviar por WhatsApp": `https://wa.me/55{só dígitos}?text=` + `encodeURIComponent('Olá, {nome}! Bem-vindo(a) à {empresa}. Para a sua admissão, preencha seus dados e envie os documentos por este link: {url}')`.
- Situação do link: `status`, `expira_em`, documentos recebidos.
- "Pedir correção": `rpc('sol_admissao_pedir_correcao', { p_solicitacao, p_msg })`. Reabre o link com o recado.

**d) Enviar ao colaborador (equipe):** três modelos prontos, com texto editável antes de enviar.

| Botão | Arquivo | Pede de volta (`p_retorno`) |
|---|---|---|
| Guia do exame admissional | gerada automaticamente (seção 5) | `Exame admissional (ASO)` |
| Carta de abertura de conta salário | PDF anexado pela equipe | `Comprovante da conta salário` |
| Aviso: contrato enviado para assinatura | sem arquivo (a assinatura é no sistema de ponto) | — |

- **Com arquivo:**
  1. Upload em `solicitacoes/admissao/{token}/equipe/{nome}`.
  2. `rpc('sol_admissao_enviar_doc', { p_solicitacao, p_titulo, p_caminho, p_nome, p_instrucoes, p_retorno })`.
- **Só aviso:** `rpc('sol_admissao_avisar', { p_solicitacao, p_titulo, p_texto })`.
- **Depois de enviar:** abrir o WhatsApp do colaborador avisando que há documento no link.
- **Na tela:** listar `sol_admissao_envios` com a situação. Se `retorno_anexo_id` estiver vazio, mostrar "Aguardando …"; senão, "✓ recebido".

**e) Gerar ficha de admissão (equipe):** seção 6.

## 4. Página pública do colaborador: `admissao.html?t={token}` (pronta, arquivo `admissao.html`)

Rota **sem login**, usando a chave pública (anon). Layout para celular, com o cabeçalho verde do ERP.

**Ao abrir:** `rpc('sol_admissao_abrir', { p_token })`.
- `ok:false`: mostrar mensagem amigável conforme `motivo`:
  - `invalido`: link inválido.
  - `expirado`: link vencido, falar com o RH.
  - `concluida`: admissão finalizada.
- `ok:true` traz: `modo` (`formulario` | `acompanhamento`), `empresa`, `cargo`, `horario`, `data_inicio`, `pede_uniforme`, `status`, `correcao` (recado do RH), `dados` (rascunho salvo), `documentos` (lista conforme o cargo), `unidades` (Corpori), `arquivos` já enviados, `envios` do RH.

### 4.1 Modo formulário: 5 passos, com barra de progresso
Os nomes das chaves abaixo são **exatos**, porque o banco valida por eles. Datas em `AAAA-MM-DD`.

1. **Dados pessoais:** `nome`, `nome_social`, `nome_mae`, `nome_pai`, `nascimento`, `sexo` (`F`|`M`), `local_nascimento`, `raca_cor` (Branca | Preta | Parda | Amarela | Indígena | Não informado), `estado_civil`, `escolaridade`.
2. **Documentos, contato e endereço:**
   - `cpf`, `rg`, `rg_orgao`, `rg_emissao`, `email`, `telefone`.
   - `cep`: preencher o endereço automaticamente pelo ViaCEP (`https://viacep.com.br/ws/{cep}/json/`).
   - `endereco`, `complemento`, `bairro`, `cidade`.
   - `vale_transporte` (`sim`|`nao`) e, se sim, `vt_linha`.
   - Se `pede_uniforme`: `tamanho_calcado`, `tamanho_roupa`.
   - **Exame admissional:**
     - `exame_unidade`: nome de uma das `unidades`.
     - `exame_data`: `o quanto antes` ou uma data.
     - `exame_turno`: `manhã`|`tarde`.
3. **Família:**
   - `tem_conjuge` (`sim`|`nao`) → `conjuge_nome`, `conjuge_naturalidade`, `conjuge_nascimento`.
   - `tem_dependentes` (`sim`|`nao`) → `dependentes: [{ nome, parentesco, nascimento, cpf }]`, **sem limite de quantidade**.
4. **Envio de documentos:** lista filtrada de `documentos` pela regra (`obrigatorio`):
   - `sempre`: obrigatório.
   - `conjuge`: obrigatório se `tem_conjuge = sim`.
   - `dependentes`: obrigatório se `tem_dependentes = sim`.
   - `filhos`: obrigatório se algum dependente tem parentesco "Filho(a)".
   - `opcional`: mostrar como "Se houver".
5. **Revisar e enviar:**
   - Lista do que falta, com botão "Corrigir" que leva ao passo.
   - Caixa obrigatória de LGPD: "Autorizo o uso dos meus dados e documentos pela {empresa} e pela Controlacs exclusivamente para a minha admissão e as obrigações trabalhistas."

**Salvar rascunho:** a cada passo, `rpc('sol_admissao_salvar', { p_token, p_dados, p_enviar: false })`.

**Upload de documento:**
1. Comprimir imagens no navegador: lado máximo de 2000 px, JPEG com qualidade 0,8.
2. `storage.from('solicitacoes').upload('admissao/' + token + '/' + crypto.randomUUID() + '.' + ext, file)`. A raiz da pasta do token aceita só pdf, jpg, jpeg, png, heic e webp.
3. `rpc('sol_admissao_anexar', { p_token, p_caminho, p_nome, p_documento: <nome exato da lista>, p_mime, p_tamanho })`.

**Trocar arquivo:** `rpc('sol_admissao_remover', { p_token, p_anexo })`, depois um novo envio.

**Enviar:** `rpc('sol_admissao_salvar', { p_token, p_dados, p_enviar: true, p_consentimento: true })`.
- Se faltar algo, volta `{ ok:false, faltam:[…] }`: mostrar a lista.
- Se der certo, volta `{ ok:true }`: mostrar a tela "Tudo enviado!".

Se `status = 'correcao'`, mostrar no topo o recado `correcao` e reabrir o formulário com o rascunho.

### 4.2 Modo acompanhamento (depois do envio)
Mostrar "Seus dados já estão com o RH" e os cartões de `envios`:
- **Baixar:** `storage.from('solicitacoes').createSignedUrl(caminho, 300)`. A anon tem permissão só na pasta `equipe` do token.
- **Devolver**, quando `retorno` estiver preenchido e `retorno_enviado = false`:
  1. Upload em `admissao/{token}/retorno/{uuid}.{ext}`.
  2. `rpc('sol_admissao_anexar', { …, p_documento: envio.retorno })`.
- **Aviso sem arquivo:** só o texto.

## 5. Guia de autorização de exames (Corpori): preenchimento automático

- **Modelo:** arquivo do próprio site, `modelos/guia_corpori.pdf` (neste repositório; carregar com `fetch('modelos/guia_corpori.pdf')`). É um PDF editável com campos AcroForm.
- **Ferramenta:** preencher no navegador com **pdf-lib**: `PDFDocument.load` → `getForm()`. 
- **Botão:** "Gerar guia do ASO", disponível a partir da etapa 4.
- **Antes de enviar:** mostrar a pré-visualização para a equipe conferir.
- **Envio:**
  1. Upload em `admissao/{token}/equipe/guia_exame_{nome}.pdf`.
  2. `sol_admissao_enviar_doc` com `p_retorno = 'Exame admissional (ASO)'`.
  3. Botão "Enviar à unidade": `wa.me/55{sol_clinica_unidades.whatsapp}` da unidade escolhida.

| Campo do PDF | Valor |
|---|---|
| `razao_social`, `cnpj` | `clientes.nome` / `clientes.cnpj` (usar a razão social, se o ERP tiver em `clientes.ficha`) |
| `nome_funcionario` | `dados.nome` |
| `cpf` | `dados.cpf` |
| `setor` | `sol_admissoes.setor` |
| `cargo` | `sol_admissoes.cargo_nome` |
| `data_nascimento` | `dados.nascimento` em dd/mm/aaaa |
| `matricula_esocial` | vazio |
| `data_admissao` | `sol_solicitacoes.dados.data_inicio` em dd/mm/aaaa |
| `sexo_m` / `sexo_f` | marcar conforme `dados.sexo` |
| `exame_01` | marcar (Admissional) |
| `aptidao_01`…`05` | marcar as de `sol_cargos.aptidoes`: Postos de Combustíveis = 01, Trabalho em Altura = 02, Manipulação de Alimentos = 03, Espaço Confinado = 04, Serviços de Eletricidade = 05 |
| `unidade_1`…`5` | `sol_clinica_unidades.campo_pdf` da unidade em `dados.exame_unidade` |
| `agendamento_data` | "O quanto antes" ou a data sugerida |
| `agendamento_hora` | "Manhã" / "Tarde" (de `dados.exame_turno`) |

Nos checkboxes, use `form.getCheckBox(nome).check()`. O valor ligado é `/Yes`.

## 6. Ficha de admissão para a contabilidade (modelo próprio)

- **Botão:** "Gerar ficha", disponível a partir da etapa 4, com escolha entre **PDF** (jsPDF ou pdf-lib) e **Excel** (SheetJS/xlsx).
- **Layout:** cabeçalho verde do ERP e seções em grade de 3 colunas (rótulo pequeno em cinza, valor em negrito).
- **Seções:**
  - Empresa: nome, CNPJ, gestor solicitante.
  - Admissão: cargo, setor, salário, horário, início, experiência e vencimentos, vale-transporte, uniforme.
  - Dados pessoais e documentos, incluindo o Coren quando houver.
  - Endereço e contato.
  - Cônjuge.
  - Dependentes, em tabela.
  - Documentos anexados.
  - Rodapé com a data do aceite LGPD (`consentimento_em`) e quem conferiu.
- **Opções:** baixar, ou anexar à conversa e enviar à contabilidade (e-mail), opcionalmente com um .zip dos anexos.

## 7. Visual (igual ao ERP)

- **Cabeçalho:** `#1B3B37`, logo em caixa branca, "PORTAL DO CLIENTE", seletor de empresa, ícones com contador vermelho `#D93025`.
- **Abas em fundo branco:** a ativa em pílula `#1F4744` com texto branco.
- **Fundo:** `#F3F5F5`. **Cards:** brancos, borda `#E2E7E6`, raio 10 px.
- **Texto:** `#1A2422`, secundário `#5E6B68`. **Botão primário:** `#1F4744`.
- **Status:**

| Status | Fundo | Texto |
|---|---|---|
| aberta | `#E3F1EF` | `#1A5A54` |
| em andamento | `#E6EDF7` | `#2A4C80` |
| aguardando cliente | `#FCE9E1` | `#93361A` |
| concluída | `#E4F2E6` | `#1D6430` |

- **Saudação:** em maiúsculas pequenas, por exemplo "BOA NOITE, CAROL".
- **Fonte:** a mesma do ERP.

## 8. Testes de aceitação
1. Um cliente de uma empresa não vê solicitações de outra empresa.
2. Um usuário do tipo colaborador vê só as próprias solicitações.
3. O cliente não vê notas internas nem anexos internos.
4. A resposta do cliente muda "aguardando cliente" para "em andamento".
5. O fluxo completo da admissão funciona:
   - o gestor pede;
   - a equipe gera o link;
   - o colaborador preenche pelo celular, sem login, e envia;
   - a etapa vai para 4;
   - a equipe preenche o setor, gera e envia a guia;
   - o colaborador baixa a guia e devolve o ASO;
   - a equipe gera a ficha e conclui (etapa 7);
   - o link deixa de abrir.
6. Um link vencido ou um token errado mostra a mensagem amigável e não expõe nenhum dado.
