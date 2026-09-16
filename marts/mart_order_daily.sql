-- date × attribution × device × geo

{{ config(
    materialized = 'table',
    cluster_by = [
        'attribution_key',
        'device_key',
        'geo_key'
    ]
) }}

select

    o.order_date,

    c.year,
    c.quarter,
    c.month,
    c.month_name,
    c.year_month,
    c.week_start,
    c.month_start,
    c.is_weekend,

    o.geo_key,
    o.device_key,
    o.attribution_key,

    a.source,
    a.medium,
    a.campaign,

    d.device_category,
    d.os,
    d.browser,

    g.continent,
    g.country,
    g.region,
    g.city,

    count(distinct o.order_key) as orders,

    sum(coalesce(o.purchase_revenue, 0))
        as revenue,

    sum(coalesce(o.purchase_revenue_usd, 0))
        as revenue_usd,

    sum(coalesce(o.unique_items, 0))
        as unique_items,

    count(distinct o.user_pseudo_id)
        as purchasing_users

from {{ ref('fct_orders') }} o

left join {{ ref('dim_calendar') }} c
on o.order_date = c.date_key

left join {{ ref('dim_geo') }} g
    on o.geo_key = g.geo_key

left join {{ ref('dim_device') }} d
    on o.device_key = d.device_key

left join {{ ref('dim_attribution') }} a
    on o.attribution_key = a.attribution_key

group by all
