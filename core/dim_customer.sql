{{ config(
    materialized = 'table'
) }}

with sessions as (

    select
        user_pseudo_id,

        min(session_date) as first_session_date,
        max(session_date) as last_session_date,

        count(distinct session_id) as lifetime_sessions

    from {{ ref('fct_sessions') }}

    where user_pseudo_id is not null

    group by 1

),

orders as (

    select

        user_pseudo_id,

        min(order_date) as first_order_date,
        max(order_date) as last_order_date,

        count(distinct order_key) as lifetime_orders,

        sum(coalesce(purchase_revenue, 0))
            as lifetime_revenue

    from {{ ref('fct_orders') }}

    where user_pseudo_id is not null

    group by 1

)

select

    coalesce(
        s.user_pseudo_id,
        o.user_pseudo_id
    ) as customer_key,

    coalesce(
        s.user_pseudo_id,
        o.user_pseudo_id
    ) as user_pseudo_id,

    s.first_session_date,
    s.last_session_date,

    o.first_order_date,
    o.last_order_date,

    coalesce(s.lifetime_sessions, 0)
        as lifetime_sessions,

    coalesce(o.lifetime_orders, 0)
        as lifetime_orders,

    coalesce(o.lifetime_revenue, 0)
        as lifetime_revenue,

    case
        when o.user_pseudo_id is not null
            then true
        else false
    end as is_customer,

    case
        when o.lifetime_orders >= 2
            then true
        else false
    end as is_repeat_customer

from sessions s

full outer join orders o
    on s.user_pseudo_id = o.user_pseudo_id
