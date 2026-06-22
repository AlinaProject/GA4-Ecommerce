-- Перевірка: к-сть замовлень в int_sessions (через order_key) = к-сть в fct_orders

with sessions_orders as (
    select sum(transaction_count) as total_orders_in_sessions
    from {{ ref('int_sessions') }}
),

fct_orders_total as (
    select count(*) as total_orders_in_fct
    from {{ ref('fct_orders') }}
)

select *
from sessions_orders s
cross join fct_orders_total f
where s.total_orders_in_sessions != f.total_orders_in_fct

