-- 1 row = session_date × attribution × device × geo
 
{{ config(
    materialized = 'table',
    
    cluster_by = [
        'session_attribution_key',
        'device_key',
        'geo_key'
    ]
) }}

select

    s.session_date as date_key,

    c.year,
    c.quarter,
    c.month,
    c.month_name,
    c.year_month,
    c.week_start,
    c.month_start,
    c.is_weekend,

    s.session_attribution_key,
    s.device_key,
    s.geo_key,

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

    count(*) as sessions,

    count(distinct s.user_pseudo_id) as users,

    sum(s.total_events) as events,
    sum(s.pageviews) as pageviews,
    sum(s.item_views) as item_views,
    sum(s.add_to_cart_count) as add_to_cart_events,
    sum(s.checkouts) as checkout_events,

    sum(s.transaction_count) as orders,

    sum(coalesce(s.session_revenue, 0)) as revenue,

    countif(s.converted) as converting_sessions,

    countif(s.reached_item_view) as item_view_sessions,
    countif(s.reached_cart) as cart_sessions,
    countif(s.reached_checkout) as checkout_sessions,
    countif(s.reached_shipping) as shipping_sessions,
    countif(s.reached_payment) as payment_sessions,
    countif(s.reached_purchase) as purchase_sessions_raw,

    countif(s.is_single_event_or_zero_duration)
        as single_event_sessions,

    countif(s.is_clean_session)
        as clean_sessions,

    sum(s.total_engagement_msec)
        as total_engagement_msec,

    sum(s.session_duration_min)
        as total_session_duration_min,

    safe_divide(
        countif(s.converted),
        count(*)
    ) as conversion_rate,

    safe_divide(
        sum(s.session_revenue),
        sum(s.transaction_count)
    ) as aov,

    safe_divide(
        sum(s.session_revenue),
        count(*)
    ) as revenue_per_session,

    safe_divide(
        sum(s.session_revenue),
        count(distinct s.user_pseudo_id)
    ) as revenue_per_identified_user,

    safe_divide(
        sum(s.session_duration_min),
        count(*)
    ) as avg_session_duration_min,

    safe_divide(
        sum(s.total_engagement_msec),
        count(*)
    ) / 1000 / 60 as avg_engagement_minutes,

    safe_divide(
        countif(s.is_single_event_or_zero_duration),
        count(*)
    ) as single_event_session_rate,

    safe_divide(
        countif(s.is_clean_session),
        count(*)
    ) as clean_session_rate,

    safe_divide(
        countif(s.reached_item_view),
        count(*)
    ) as item_view_rate,

    safe_divide(
        countif(s.reached_cart),
        count(*)
    ) as cart_rate,

    safe_divide(
        countif(s.reached_checkout),
        count(*)
    ) as checkout_rate,

    safe_divide(
        countif(s.reached_shipping),
        count(*)
    ) as shipping_rate,

    safe_divide(
        countif(s.reached_payment),
        count(*)
    ) as payment_rate,

    safe_divide(
        countif(s.reached_purchase),
        count(*)
    ) as purchase_rate

from {{ ref('fct_sessions') }} s

left join {{ ref('dim_calendar') }} c
    on s.session_date = c.date_key

left join {{ ref('dim_geo') }} g
    on s.geo_key = g.geo_key

left join {{ ref('dim_device') }} d
    on s.device_key = d.device_key

left join {{ ref('dim_attribution') }} a
    on s.session_attribution_key = a.attribution_key

group by all
