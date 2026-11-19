# Contratos da Controlacs: importar, modelos e gerar para assinatura

Pedido da Carol (19/11/2026), em Gestão Controlacs › Clientes e Contratos e reajustes.

## O que faz
- **📄 Importar contrato** (PDF, inclusive escaneado, ou Word .docx): lê contratante e contratada (razão social, CNPJ, endereço, representante e CPF), o e-mail de quem assinou pela Autentique, os serviços (RH/financeiro), a mensalidade, a auditoria inicial, a taxa de visita, o limite de colaboradores, o vencimento, o índice, a vigência, o aviso prévio, o foro e a data. A Carol confere e grava: cliente (só campos vazios + `extra.representante`), contrato (`ctl_contratos`, com `extra.kt`), arquivo (`ctl_documentos`) e, se marcar, um modelo. Tudo com Desfazer (botão na própria janela, porque o aviso fica atrás do modal).
- **📝 Modelos de contrato**: o **modelo padrão melhorado** fica no código (`KT_PADRAO_TXT`, sem dado pessoal). Os modelos da Carol ficam na tabela `ctl_modelos_contrato`.
- **📝 Gerar contrato pelo modelo** (dentro do contrato): preenche com ficha + cliente + contrato, mostra a prévia, gera o PDF (pdf-lib), guarda em `ctl_documentos` e abre o envio para a Autentique (`ctAbreAss(c,pre)`) com quem assina preenchido.
- **Regra da Carol (19/11):** o reajuste deixa claro que o **volume de demandas** muda o valor (financeiro: faturamento, lançamentos e conferências; RH: quadro de colaboradores). Está na cláusula de remuneração do modelo padrão.

## Formato do modelo
- `# título`, `### subtítulo`, `## TÍTULO DA CLÁUSULA` (o "CLÁUSULA PRIMEIRA…" sai sozinho), `+` item, `++` subitem, `+++`, `-` marcador, `**negrito**`, `>>` alinhado à direita, `{{assinaturas}}`, `{{quebra}}`.
- Campos `{{nome}}` (lista em `KT_CAMPOS`) e blocos `{{#campo}}…{{/campo}}` que só entram quando o campo tem valor (`rh`, `fin`, `ambos`, `implantacao`, `valor_implantacao`, `taxa_visita`, `visitas_mes`, `limite_faturamento`…).
- Campos derivados: `*_extenso` (valores), `*_ext` (números por extenso), `titulo_servicos`, `escopo_auditoria`.

## Banco (v162, aplicado pelo SQL Editor; o SQL não fica no repositório)
Tabela `public.ctl_modelos_contrato`: `id`, `nome`, `servicos text[]` ('rh','fin'), `corpo text`, `contratada jsonb` (razao, cnpj, endereco, representante, cpf, email), `padrao jsonb` (valores padrão), `origem_documento_id` (→ `ctl_documentos`), `ativo`, `excluido_em` (excluir = desfazer), `extra jsonb` (`anterior` = versão antes da última alteração; `trocas`), `criado_em`, `atualizado_em`. RLS `ctl_master` = `eh_admin()`, como as outras `ctl_*`.
Sem a v162 a tela funciona com o modelo padrão (não salva modelos).

Colunas já existentes usadas (sem alteração de estrutura): `ctl_clientes.extra.representante {nome,cpf,email}` e `ctl_contratos.extra.kt {rh,fin,campos,modelo_id,importado}`.
