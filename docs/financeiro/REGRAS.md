# Regras do financeiro (decididas com a Carol)

Antes de mexer na Conciliação bancária, na Remessa ou no Repasse, leia isto: são casos reais que já deram problema.

## Conciliação bancária
1. **Linha somada pelo banco.** O banco pode somar numa linha só vários Pix do mesmo dia com o mesmo histórico (`fin_ofx.qtd > 1`, valores em `itens`). Cada valor da soma tem que achar o seu lançamento ou a sua conta em aberto (`gcSomaDe`). Nunca deixar como "Sem lançamento" se os pagamentos já existem, porque a equipe lançaria de novo. Caso: Platano, 05/11, MPA PB.
2. **Ligar.** Cada linha do banco tem o botão **Ligar**, para escolher à mão os lançamentos do sistema (com caixa de seleção e total) que formam a linha. A lista começa pelos de valor igual e mostra também os lançamentos de outras contas da empresa (transferência).
3. **Transferência entre contas da empresa.** Se o mesmo valor saiu de uma conta e entrou em outra (até 3 dias), e uma das pernas foi lançada como avulsa, a conciliação sugere "Transferência de/para X".
   - Ao aprovar, cria a perna que faltava, liga as duas pelo `transf_id`, limpa o `validar` e valida o item de tarefa desse lançamento.
   - Caso: Pix de R$ 90.000 do PagBank para o Inter em 09/11, MPA PB.
4. **Gerar tarefa.** Linha do banco que ninguém sabe o que é: selecione e use "📋 Gerar tarefa".
   - Entra na tarefa "Conciliação: lançamentos do banco a identificar" da empresa (`tarefa_lancamentos.ofx_id`).
   - A linha mostra "Em tarefa" até validar.
5. **Total da seleção.** A barra de seleção mostra o total das linhas marcadas: só saídas, só entradas, ou o saldo.
6. **Extrato importado vale para todos.** Fica gravado no banco de dados, pendente até conciliar ou ignorar. Importar o mesmo extrato de novo não duplica as linhas (índice único `conta_id, chave`).

## Remessa (CNAB)
1. **Numeração.** O banco espera o número seguinte ao último arquivo que ele **aceitou**; arquivo recusado não conta.
   - **"Sequencial fora de ordem":** NÃO liberar o número (responder "Cancelar" na 2ª pergunta do cancelamento) e acertar o "Nº da última remessa" da conta.
   - Recusa por erro nos dados: liberar.
   - Caso: Sicredi da MPA Pato Branco nunca tinha aceitado arquivo, e esperava o nº 1.
2. **Conta bancária lenta ao salvar.** O trigger `fin_contas_ligar_tes_upd` só refaz a tesouraria quando o nome, o `conta_bc`, o tipo ou o "ativo" mudam (migration `fin_contas_ligar_tes_so_quando_muda`).

## Repasse
1. **A busca procura em todas as colunas:** parceiro, CPF/CNPJ, guias, valor, valor da NF, nota fiscal, conta e Pix, Pagar em, situação e protocolo.

## Rotina diária
1. **Fornecedor é opcional.** Na conferência do Bom Controle, o fornecedor pode ficar em branco (`fornecedor_bc = '-'`).
2. **"+ Cadastrar" fornecedor** no lançamento do escritório.
3. **Ler o documento anexado:** em toda saída ou despesa (boletos e notas, cartão, tesouraria, saídas do caixa).
