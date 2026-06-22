{{
  config(
    materialized = 'view',
    description  = 'Один рядок = одна сесія. Revenue і transaction_count з fct_orders (єдине джерело правди).'
  )
}}

with events as (
    select * from {{ ref('stg_ga4__events') }}
),

sessions as (
    select

        user_pseudo_id,
        ga_session_id,
        session_number,
        concat(user_pseudo_id, '-', cast(ga_session_id as string)) as session_id,

        min(event_at)                                as session_start_at,
        max(event_at)                                as session_end_at,
        min(event_date_dt)                           as session_date,
        timestamp_diff(max(event_at), min(event_at), minute) as session_duration_min,

        any_value(session_source   having min event_at) as source,
        any_value(session_medium   having min event_at) as medium,
        any_value(session_campaign having min event_at) as campaign,
        any_value(channel_group    having min event_at) as channel_group,
        any_value(device_category  having min event_at) as device_category,
        any_value(os               having min event_at) as os,
        any_value(browser          having min event_at) as browser,
        any_value(country          having min event_at) as country,
        any_value(city             having min event_at) as city,

        count(*)                                     as total_events,
        countif(is_page_view)                        as pageviews,
        countif(is_view_item)                        as item_views,
        countif(is_session_engaged)                  as engaged_events,
        countif(is_add_to_cart)                      as add_to_cart_count,
        countif(is_begin_checkout)                   as checkouts,

        -- DQ-моніторинг: СИРИЙ лічильник purchase подій (з дублями).
        -- НІКОЛИ не використовувати для revenue/transaction_count.
        -- purchase_events_raw - transaction_count = к-сть GTM double-fire
        countif(is_purchase)                         as purchase_events_raw,

        sum(engagement_time_msec)                    as total_engagement_msec,

        max(case when is_view_item         then 1 else 0 end) as reached_item_view,
        max(case when is_add_to_cart       then 1 else 0 end) as reached_cart,
        max(case when is_begin_checkout    then 1 else 0 end) as reached_checkout,
        max(case when is_add_shipping_info then 1 else 0 end) as reached_shipping,
        max(case when is_add_payment_info  then 1 else 0 end) as reached_payment,
        max(case when is_purchase          then 1 else 0 end) as reached_purchase,

        count(*) > 200                               as is_high_event_session,
        timestamp_diff(max(event_at), min(event_at), minute) > 1440 as is_impossible_duration,
        max(case when is_first_visit       then 1 else 0 end) = 1 as is_new_user,
        max(case when is_gdpr_deleted      then 1 else 0 end) = 1 as has_gdpr_deleted,
        max(case when is_internal_referral then 1 else 0 end) = 1 as is_internal

    from events
    where ga_session_id is not null
    group by 1, 2, 3
),

-- ── ЄДИНЕ ДЖЕРЕЛО ПРАВДИ ДЛЯ REVENUE ────────────────────────────
-- order_key, НЕ transaction_id (транзакц.ID не унікальний — 15 колізій знайдено)
orders_by_session as (
    select
        session_id,
        count(distinct order_key) as transaction_count,
        sum(revenue)                   as session_revenue
    from {{ ref('fct_orders') }}
    group by 1
),

sessions_with_orders as (
    select
        s.*,
        coalesce(o.transaction_count, 0) as transaction_count,
        coalesce(o.session_revenue, 0)   as session_revenue
    from sessions s
    left join orders_by_session o
        on s.session_id = o.session_id
),

final as (
    select
        *,
        reached_purchase = 1                       as converted,
        total_events = 1 or session_duration_min = 0 as is_bounce,
        round(total_engagement_msec / 1000 / 60, 2)  as engagement_minutes,

        case
            when is_impossible_duration then 'invalid'
            when is_high_event_session  then 'suspicious'
            else 'normal'
        end                                          as session_quality,

        case
            when session_duration_min <= 1  then '0-1 min'
            when session_duration_min <= 5  then '1-5 min'
            when session_duration_min <= 15 then '5-15 min'
            when session_duration_min <= 30 then '15-30 min'
            else '30+ min'
        end                                          as duration_bucket,

        not is_high_event_session
          and not is_impossible_duration              as is_clean_session

    from sessions_with_orders
)

select * from final