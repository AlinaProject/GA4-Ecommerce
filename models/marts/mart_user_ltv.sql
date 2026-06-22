{{
  config(
    materialized = 'table',
    description  = 'Тонкий шар над int_user_metrics для BI-споживання. Не дублює розрахунки — лише пере-виставляє готову модель під назвою, зручною для Tableau.'
  )
}}

select * from {{ ref('int_user_metrics') }}