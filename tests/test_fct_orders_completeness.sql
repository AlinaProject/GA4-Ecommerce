-- Перевірка: чи кожен transaction_id присутній у fct_orders хоча б раз
-- (НЕ точна кількість — 1 transaction_id тепер може = кілька order_key)

with source_txn_ids as (
    select distinct transaction_id
    from {{ ref('stg_ga4__events') }}
    where is_purchase = true and flag_missing_txn_id = false
),
fct_txn_ids as (
    select distinct transaction_id
    from {{ ref('fct_orders') }}
)
select s.transaction_id
from source_txn_ids s
left join fct_txn_ids f using (transaction_id)
where f.transaction_id is null