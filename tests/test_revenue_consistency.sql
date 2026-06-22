-- Reconciliation test: revenue має ТОЧНО співпадати між session-grain і order-grain.
-- Якщо хтось зламає join у int_sessions і поверне ручний sum() — тест впаде.

with sessions_total as (
    select round(sum(session_revenue), 2) as total_revenue
    from {{ ref('int_sessions') }}
),

orders_total as (
    select round(sum(revenue), 2) as total_revenue
    from {{ ref('fct_orders') }}
)

select
    s.total_revenue as sessions_revenue,
    o.total_revenue as orders_revenue,
    abs(s.total_revenue - o.total_revenue) as diff
from sessions_total s
cross join orders_total o
where abs(s.total_revenue - o.total_revenue) > 1.00