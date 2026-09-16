{{
  config(
    materialized = 'view',
    description  = 'Grain = 1 session.'
  )
}}

with events as (

    select 
        event_date,
        event_date_dt,
        event_at,
        event_timestamp,
        event_name,
        event_previous_timestamp,
        user_pseudo_id,
        user_id,
        event_bundle_sequence_id,
        event_server_timestamp_offset,
        platform,
        has_null_user_pseudo_id,
        ga_session_id,
        session_number,
        session_key,
        page_location,
        page_title,
        page_referrer,
        session_engaged_raw,
        engagement_time_msec,
        event_source,
        event_medium,
        event_campaign,
        first_touch_source,
        first_touch_medium,
        first_touch_campaign,
        device_category,
        os,
        browser,
        language,
        continent,
        country,
        region,
        city,
        transaction_id_raw,
        transaction_id_normalized,
        transaction_id_status,
        purchase_revenue,
        purchase_revenue_usd,
        tax_value,
        shipping_value,
        unique_items,
        items,
        items_revenue,
        items_quantity,
        item_to_purchase_revenue_diff,
        flag_item_purchase_revenue_mismatch,
        technical_event_fingerprint,
        is_purchase,
        is_add_to_cart,
        is_begin_checkout,
        is_add_payment_info,
        is_add_shipping_info,
        is_view_item,
        is_page_view,
        is_session_start,
        is_first_visit,
        is_engaged_session_event,
        flag_missing_transaction_id,
        flag_null_purchase_revenue,
        flag_negative_purchase_revenue,
        flag_missing_session_id,
        flag_self_referral,
        flag_event_self_referral,
        flag_data_deleted
    
    from {{ ref('stg_ga4__events') }}

),

sessions as (

    select

        e.session_key as session_id,
        e.user_pseudo_id,
        e.ga_session_id,
        e.session_number,

        min(e.event_at) as session_start_at,
        max(e.event_at) as session_end_at,
        min(e.event_date_dt) as session_date,

        timestamp_diff(
            max(e.event_at),
            min(e.event_at),
            minute
        ) as session_duration_min,

        -- =====================================================
        -- Session attribution
        -- =====================================================

        array_agg(
            if(
                e.event_source is not null
                or e.event_medium is not null
                or e.event_campaign is not null,

                struct(
                    e.event_source as source,
                    e.event_medium as medium,
                    e.event_campaign as campaign
                ),

                null
            )
            ignore nulls
            order by e.event_at asc
            limit 1
        )[safe_offset(0)] as session_attribution,

        -- =====================================================
        -- Device
        -- =====================================================

        array_agg(
            e.device_category ignore nulls
            order by e.event_at asc
            limit 1
        )[safe_offset(0)] as device_category,

        array_agg(
            e.os ignore nulls
            order by e.event_at asc
            limit 1
        )[safe_offset(0)] as os,

        array_agg(
            e.browser ignore nulls
            order by e.event_at asc
            limit 1
        )[safe_offset(0)] as browser,

        -- =====================================================
        -- Geo
        -- =====================================================

        array_agg(
            e.continent ignore nulls
            order by e.event_at asc
            limit 1
        )[safe_offset(0)] as continent,

        array_agg(
            e.country ignore nulls
            order by e.event_at asc
            limit 1
        )[safe_offset(0)] as country,

        array_agg(
            e.region ignore nulls
            order by e.event_at asc
            limit 1
        )[safe_offset(0)] as region,

        array_agg(
            e.city ignore nulls
            order by e.event_at asc
            limit 1
        )[safe_offset(0)] as city,

        -- =====================================================
        -- Event metrics. These are event-level/session-level metrics.
        -- =====================================================

        count(*) as total_events,

        countif(e.is_page_view) as pageviews,

        countif(e.is_view_item) as item_views,

        countif(e.is_engaged_session_event) as engaged_events,

        countif(e.is_add_to_cart) as add_to_cart_count,

        countif(e.is_begin_checkout) as checkouts,

        -- Raw purchase events.
        -- Used for DQ only.
        countif(e.is_purchase) as purchase_events_raw,

        -- =====================================================
        -- Engagement
        -- =====================================================

        sum(
            coalesce(
                e.engagement_time_msec,
                0
            )
        ) as total_engagement_msec,

        -- =====================================================
        -- Funnel
        -- =====================================================

        countif(e.is_view_item) > 0 as reached_item_view,

        countif(e.is_add_to_cart) > 0 as reached_cart,
        
        countif(e.is_begin_checkout) > 0 as reached_checkout,
        
        countif(e.is_add_shipping_info) > 0 as reached_shipping,

        countif(e.is_add_payment_info) > 0 as reached_payment,

        countif(e.is_purchase) > 0 as reached_purchase,

        -- =====================================================
        -- Session DQ
        -- =====================================================

        count(*) > 200 as is_high_event_session,

        timestamp_diff(
            max(e.event_at),
            min(e.event_at),
            minute
        ) > 1440 as is_impossible_duration,

        max(
            if(e.is_first_visit, 1, 0)
        ) = 1 as is_first_visit_session,

        max(
            if(e.flag_data_deleted, 1, 0)
        ) = 1 as has_gdpr_deleted,

        max(
            if(e.flag_self_referral, 1, 0)
        ) = 1 as has_self_referral

    from events e

    where e.session_key is not null

    group by
        e.session_key,
        e.user_pseudo_id,
        e.ga_session_id,
        e.session_number
)

select f.session_id,
    f.user_pseudo_id,
    f.ga_session_id,
    f.session_number,
    f.session_start_at,
    f.session_end_at,
    f.session_date,
    f.session_duration_min,
    f.session_attribution,
    f.device_category,
    f.os,
    f.browser,
    f.continent,
    f.country,
    f.region,
    f.city,
    f.total_events,
    f.pageviews,
    f.item_views,
    f.engaged_events,
    f.add_to_cart_count,
    f.checkouts,
    f.purchase_events_raw,
    f.total_engagement_msec,
    f.reached_item_view,
    f.reached_cart,
    f.reached_checkout,
    f.reached_shipping,
    f.reached_payment,
    f.reached_purchase,
    f.is_high_event_session,
    f.is_impossible_duration,
    f.is_first_visit_session,
    f.has_gdpr_deleted,
    f.has_self_referral
    
from sessions f
