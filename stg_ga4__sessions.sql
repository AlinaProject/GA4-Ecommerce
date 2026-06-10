{{
  config(
    materialized = 'view',
    description  = 'Один рядок = одна сесія. Агрегація з stg_ga4__events.'
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

        -- Унікальний ключ сесії
        concat(user_pseudo_id, '-', cast(ga_session_id as string)) as session_id,

        -- Timing
        min(event_at)                               as session_start_at,
        max(event_at)                               as session_end_at,
        min(event_date_dt)                          as session_date,

        timestamp_diff(
            max(event_at), min(event_at), minute
        )                                           as session_duration_min,

        -- Attribution (перша подія сесії)
        any_value(session_source  having min event_at) as source,
        any_value(session_medium  having min event_at) as medium,
        any_value(session_campaign having min event_at) as campaign,
        any_value(channel_group   having min event_at) as channel_group,

        -- Device & Geo
        any_value(device_category having min event_at) as device_category,
        any_value(os              having min event_at) as os,
        any_value(browser         having min event_at) as browser,
        any_value(country         having min event_at) as country,
        any_value(city            having min event_at) as city,

        -- Activity counts
        count(*)                                    as total_events,
        countif(is_page_view)                       as pageviews,
        countif(is_view_item)                       as item_views,
        countif(is_session_engaged)                 as engaged_events,
        countif(is_add_to_cart)                     as add_to_cart_count,
        countif(is_begin_checkout)                  as checkouts,
        countif(is_purchase)                        as purchases,
        sum(engagement_time_msec)                   as total_engagement_msec,

        -- Funnel flags
        max(case when is_view_item         then 1 else 0 end) as reached_item_view,
        max(case when is_add_to_cart       then 1 else 0 end) as reached_cart,
        max(case when is_begin_checkout    then 1 else 0 end) as reached_checkout,
        max(case when is_add_shipping_info then 1 else 0 end) as reached_shipping,
        max(case when is_add_payment_info  then 1 else 0 end) as reached_payment,
        max(case when is_purchase          then 1 else 0 end) as reached_purchase,

        -- Revenue
        sum(case when is_purchase and not flag_missing_txn_id
            then purchase_revenue else 0 end)       as session_revenue,
        count(distinct case when is_purchase then transaction_id end) as transaction_count,

        -- DQ flags
        count(*) > 200                              as is_high_event_session,
        timestamp_diff(
            max(event_at), min(event_at), minute
        ) > 1440                                    as is_impossible_duration,

        max(case when is_first_visit then 1 else 0 end) = 1 as is_new_user,
        max(case when is_gdpr_deleted then 1 else 0 end) = 1 as has_gdpr_deleted,
        max(case when is_internal_referral then 1 else 0 end) = 1 as is_internal

    from events
    where ga_session_id is not null
    group by 1, 2, 3
),

final as (
    select
        *,
        reached_purchase = 1                        as converted,
        total_events = 1 or session_duration_min = 0 as is_bounce,
        not is_high_event_session
          and not is_impossible_duration             as is_clean_session
    from sessions
)

select * from final