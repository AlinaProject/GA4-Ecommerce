{{ config(
    materialized = 'table',
    description = 'One row = one resolved GA4 session. Revenue and transaction_count come exclusively from fct_orders.',
    cluster_by = [
        "session_id",
        "user_pseudo_id"
    ]
) }}

with sessions as (

    select
        session_id,
        user_pseudo_id,
        ga_session_id,
        session_number,
        session_start_at,
        session_end_at,
        session_date,
        session_duration_min,
        session_attribution,
        device_category,
        os,
        browser,
        continent,
        country,
        region,
        city,
        total_events,
        pageviews,
        item_views,
        engaged_events,
        add_to_cart_count,
        checkouts,
        purchase_events_raw,
        total_engagement_msec,
        reached_item_view,
        reached_cart,
        reached_checkout,
        reached_shipping,
        reached_payment,
        reached_purchase,
        is_high_event_session,
        is_impossible_duration,
        is_first_visit_session,
        has_gdpr_deleted,
        has_self_referral
    from {{ ref('int_sessions') }}
),

orders_by_session as (

    select
        session_id,

        count(distinct order_key)
            as transaction_count,

        sum(purchase_revenue)
            as session_revenue

    from {{ ref('fct_orders') }}

    group by 1

),

final as (

    select
        s.session_id,
        s.user_pseudo_id,
        s.ga_session_id,
        s.session_number,

        s.session_start_at,
        s.session_end_at,
        s.session_date,
        s.session_duration_min,

        /*
        Dimension FK.
        */

        {{ generate_key([
        'continent',
        'country',
        'region',
        'city'
        ]) }} as geo_key,

        {{ generate_key([
        'device_category',
        'os',
        'browser'
        ]) }} as device_key,

        {{ generate_key([
            's.session_attribution.source',
            's.session_attribution.medium',
            's.session_attribution.campaign'
        ]) }} as session_attribution_key,

        s.session_attribution,

        s.device_category,
        s.os,
        s.browser,

        s.continent,
        s.country,
        s.region,
        s.city,

        s.total_events,
        s.pageviews,
        s.item_views,
        s.engaged_events,
        s.add_to_cart_count,
        s.checkouts,
        s.purchase_events_raw,

        s.total_engagement_msec,

        s.reached_item_view,
        s.reached_cart,
        s.reached_checkout,
        s.reached_shipping,
        s.reached_payment,
        s.reached_purchase,

        /*
        Order metrics.
        Source of truth: fct_orders.
        */

        coalesce(
            o.transaction_count,
            0
        ) as transaction_count,

        coalesce(o.session_revenue, 0) as session_revenue,

        coalesce(
            o.transaction_count,
            0
        ) > 0 as converted,

        /*
        Semantic replacement for "bounce".
        */

        cast(
            (
                s.total_events = 1
                or s.session_duration_min = 0
            ) as bool
        )as is_single_event_or_zero_duration,

        round(
            s.total_engagement_msec / 1000 / 60,
            2
        ) as engagement_minutes,

        case

            when s.is_impossible_duration
                then 'invalid'

            when s.is_high_event_session
                then 'suspicious'

            else 'normal'

        end as session_quality,

        case

            when s.session_duration_min <= 1
                then '0-1 min'

            when s.session_duration_min <= 5
                then '1-5 min'

            when s.session_duration_min <= 15
                then '5-15 min'

            when s.session_duration_min <= 30
                then '15-30 min'

            else '30+ min'

        end as duration_bucket,

        cast(
            (
                not s.is_high_event_session
                and not s.is_impossible_duration
            ) as bool
        )  as is_clean_session,

        is_high_event_session,
        is_impossible_duration,
        is_first_visit_session,
        has_gdpr_deleted,
        has_self_referral

    from sessions s

    left join orders_by_session o
        on s.session_id = o.session_id

)

select 
  session_id,
  user_pseudo_id,
  ga_session_id,
  session_number,
  session_start_at,
  session_end_at,
  session_date,
  session_duration_min,
  geo_key,
  device_key,
  session_attribution_key,
  session_attribution,
  device_category,
  os,
  browser,
  continent,
  country,
  region,
  city,
  total_events,
  pageviews,
  item_views,
  engaged_events,
  add_to_cart_count,
  checkouts,
  purchase_events_raw,
  total_engagement_msec,
  reached_item_view,
  reached_cart,
  reached_checkout,
  reached_shipping,
  reached_payment,
  reached_purchase,
  transaction_count,
  session_revenue,
  converted,
  is_single_event_or_zero_duration,
  engagement_minutes,
  session_quality,
  duration_bucket,
  is_clean_session,
  is_high_event_session,
  is_impossible_duration,
  is_first_visit_session,
  has_gdpr_deleted,
  has_self_referral
from final
