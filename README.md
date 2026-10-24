# Caixas MedPrev

Sistema de fechamento de caixa da Controlacs. Site estático (index.html) publicado pelo GitHub Pages; dados e login no Supabase. Instalação do banco em supabase/schema.sql.

Atualizações do banco, rodar em ordem no SQL Editor do Supabase (todas podem rodar mais de uma vez):

1. supabase/schema.sql: instalação (caixa)
2. supabase/v2_modulos.sql: acessos por empresa e módulo; contas a pagar, cartão e tesouraria
3. supabase/v3_rh_ferias.sql: RH / férias (funcionários, períodos, programação, feriados)
4. supabase/v4_bom_controle_caixa.sql: importação do Bom Controle do caixa (conta Tesouraria por empresa, modelo das entradas)
5. supabase/v5_ferias_automatico.sql: férias sempre em dia (abre sozinho o novo período aquisitivo de cada colaborador)
