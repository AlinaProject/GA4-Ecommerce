-- Поширює reconciliation-патерн на user-grain: revenue в int_user_metrics
-- має співпадати з fct_orders. Ловить рецидив transaction_id-бага
-- якщо хтось знову порахує purchases напряму з fct_orders замість
-- через int_sessions.transaction_count.

with user_metrics_total as (
    select round(sum(total_revenue), 2) as total_revenue
    from {{ ref('int_user_metrics') }}
),

orders_total as (
    select round(sum(revenue), 2) as total_revenue
    from {{ ref('fct_orders') }}
)

select *
from user_metrics_total u
cross join orders_total o
where abs(u.total_revenue - o.total_revenue) > 1.00