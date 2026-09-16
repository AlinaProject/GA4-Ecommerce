{{ config(
    materialized = 'table'
) }}

with customer_orders as (

    select

        user_pseudo_id,

        count(distinct order_key) as orders,

        sum(coalesce(purchase_revenue, 0))
            as revenue,

        min(order_date) as first_order_date,

        max(order_date) as last_order_date,

        count(
            distinct date_trunc(order_date, month)
        ) as active_order_months

    from {{ ref('fct_orders') }}

    where user_pseudo_id is not null

    group by 1

),

metrics as (

    select

        o.user_pseudo_id,

        o.first_order_date,
        o.last_order_date,

        o.orders,
        o.revenue,
        o.active_order_months,

        safe_divide(
            o.revenue,
            o.orders
        ) as aov,

        safe_divide(
            greatest(o.orders - 1, 0),
            o.orders
        ) as repeat_order_rate,

        date_diff(
            o.last_order_date,
            o.first_order_date,
            day
        ) as observed_customer_lifespan_days,

        date_diff(
            o.last_order_date,
            o.first_order_date,
            month
        ) + 1 as observed_customer_months

    from customer_orders o

)

select

    m.user_pseudo_id,

    m.first_order_date,
    m.last_order_date,

    m.orders,
    m.revenue,

    m.aov,

    m.active_order_months,

    m.repeat_order_rate,

    m.observed_customer_lifespan_days,

    m.observed_customer_months,

    safe_divide(
        m.orders,
        greatest(m.observed_customer_months, 1)
    ) as orders_per_month,

    safe_divide(
        m.revenue,
        greatest(m.observed_customer_months, 1)
    ) as revenue_per_month,

    /*
      Simple 12-month run-rate estimate.
    */

    safe_divide(
        m.revenue,
        greatest(m.observed_customer_months, 1)
    ) * 12 as estimated_ltv_12m

from metrics m
