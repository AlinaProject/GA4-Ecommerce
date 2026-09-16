{{ config(
    materialized = 'table',
    description = 'Daily executive product performance. One row = one product per purchase date.',

    cluster_by = [
        "product_key",
        "session_attribution_key",
        "device_key",
        "geo_key"
    ]

) }}

with items as (

select

    purchase_date as date_key,

    order_key,
    session_id,
    product_key,

    item_price,
    item_quantity,
    item_revenue

from {{ ref('fct_order_items') }}

),

enriched as (

select

    i.date_key,

    i.order_key,
    i.product_key,

    i.item_price,
    i.item_quantity,
    i.item_revenue,

    s.geo_key,
    s.device_key,
    s.session_attribution_key,
    s.session_id

from items i

left join {{ ref('fct_sessions') }} s
    on i.session_id = s.session_id

)

select

    e.date_key,

    c.year,
    c.quarter,
    c.month,
    c.month_name,
    c.year_month,
    c.week_start,
    c.month_start,
    c.is_weekend,

    e.product_key,

    p.product_id,
    p.product_name,
    p.item_brand,
    p.item_variant,
    p.item_category,
    p.category_l1,
    p.category_l2,
    p.category_l3,

    e.geo_key,
    e.device_key,
    e.session_attribution_key,

    g.continent,
    g.country,
    g.region,
    g.city,

    d.device_category,
    d.os,
    d.browser,

    a.source,
    a.medium,
    a.campaign,

    count(distinct e.order_key) as orders,

    count(distinct e.session_id) as purchasing_sessions,

    sum(coalesce(e.item_quantity, 0)) as units_sold,

    sum(coalesce(e.item_revenue, 0)) as revenue,

    count(*) as order_item_rows,

    avg(e.item_price) as avg_item_price,

    safe_divide(
        sum(coalesce(e.item_revenue, 0)),
        sum(coalesce(e.item_quantity, 0))
    ) as realized_avg_price,

    safe_divide(
        sum(coalesce(e.item_revenue, 0)),
        count(distinct e.order_key)
    ) as revenue_per_order

from enriched e

left join {{ ref('dim_calendar') }} c
on e.date_key = c.date_key

left join {{ ref('dim_product') }} p
on e.product_key = p.product_key

left join {{ ref('dim_geo') }} g
on e.geo_key = g.geo_key

left join {{ ref('dim_device') }} d
on e.device_key = d.device_key

left join {{ ref('dim_attribution') }} a
on e.session_attribution_key = a.attribution_key

group by all
