# Solicitações + Admissão: o que já está no banco

Projeto Supabase **Caixas MedPrev**. Tudo aplicado em **18/11/2026**. O SQL não fica neste repositório, porque ele é público. Ele está no histórico de migrations do Supabase com os nomes abaixo.

| Migration | Conteúdo |
|---|---|
| `modulo_solicitacoes` | Tabelas `sol_tipos` (9 tipos iniciais), `sol_solicitacoes`, `sol_mensagens`, `sol_anexos`, `sol_eventos`, `sol_leituras`, `sol_notificacoes`; bucket privado `solicitacoes`; triggers de protocolo, prazo por SLA, histórico e notificações; RLS; tempo real |
| `modulo_solicitacoes_permissoes_funcoes` | Bloqueia a chamada direta das funções internas pela API |
| `admissao_link_colaborador` | `sol_cargos` (documentos extras, ex.: Coren; uniforme; aptidões da guia), `sol_clinica_unidades` (5 unidades da Corpori), `sol_admissoes` (link/token, etapas 1–7, setor, salário), `sol_admissao_envios` (o que o RH manda ao colaborador e o que ele devolve); funções `sol_admissao_*`; regras do Storage para o colaborador sem login |

## Integração com o ERP (nenhuma tabela existente foi alterada)
- **Equipe:** `eh_escritorio()` / `eh_admin()` (`perfis.papel = 'escritorio'`).
- **Cliente:** `perfis.papel = 'operador'` + `perfis.cliente_id`.
  - `tipo = 'cliente'` vê tudo da empresa.
  - `tipo = 'colaborador'` vê só o que ele mesmo abriu.
- **Acesso extra a outra empresa:** `acessos (modulo = 'solicitacoes', nivel = 'gestor' para ver tudo)`.

## Funções (RPC) para o front
- **Equipe/cliente logado:**
  - `sol_admissao_gerar_link(p_solicitacao)` → token
  - `sol_admissao_etapa(p_solicitacao, p_etapa)`
  - `sol_admissao_pedir_correcao(p_solicitacao, p_msg)`
  - `sol_admissao_enviar_doc(p_solicitacao, p_titulo, p_caminho, p_nome, p_instrucoes, p_retorno)`
  - `sol_admissao_avisar(p_solicitacao, p_titulo, p_texto)`
  - `sol_experiencia_vencimentos(p_data_inicio, p_experiencia)`
- **Colaborador sem login (anon, só com o token):**
  - `sol_admissao_abrir(p_token)`
  - `sol_admissao_salvar(p_token, p_dados, p_enviar, p_consentimento)`
  - `sol_admissao_anexar(p_token, p_caminho, p_nome, p_documento, p_mime, p_tamanho)`
  - `sol_admissao_remover(p_token, p_anexo)`

Os detalhes de uso estão em `INSTRUCOES.md`.

## Caminhos no Storage (bucket `solicitacoes`)
- `{cliente_id}/{solicitacao_id}/{arquivo}`: anexos da conversa.
- `admissao/{token}/{arquivo}`: documentos que o colaborador envia pelo formulário.
- `admissao/{token}/retorno/{arquivo}`: o que o colaborador devolve (ASO, comprovante da conta salário…).
- `admissao/{token}/equipe/{arquivo}`: o que o RH envia ao colaborador (guia, carta…).


## 20/11/2026: quem é cliente
`sol_eh_cliente(cli)`: perfil operador com `cliente_id = cli` **ou** qualquer linha em `acessos` dessa empresa. `sol_ve_tudo_cliente(cli)`: o mesmo, mas só para o tipo `cliente` (gestor). O colaborador vê só os chamados que abriu. Migration `sol_cliente_por_acesso_empresa`.
