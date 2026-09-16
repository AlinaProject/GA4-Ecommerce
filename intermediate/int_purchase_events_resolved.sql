{{ config(
    materialized = 'view',
    description = 'Canonical purchase resolution. One row = one GA4 purchase event. Resolves transaction/order identity, duplicate logic, revenue reconciliation, and canonical purchase attribution.'
) }}

with purchases as (

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
    where is_purchase = true
),

transaction_stats as (

    select

        transaction_id_normalized as stats_transaction_id_normalized,

        count(*) as transaction_purchase_events_raw,

        count(distinct user_pseudo_id) as transaction_users,

        count(distinct session_key) as transaction_sessions,

        min(event_at) as first_transaction_purchase_at

    from purchases

    where transaction_id_normalized is not null

    group by 1

),

ordered as (

    select

        p.*,

        ts.transaction_purchase_events_raw,
        ts.transaction_users,
        ts.transaction_sessions,
        ts.first_transaction_purchase_at,

        /*
        ============================================================
        Purchase instance within normalized transaction
        ============================================================
        */

        row_number() over (
            partition by p.transaction_id_normalized
            order by
                p.event_at asc,
                p.event_timestamp asc,
                coalesce(
                    p.event_bundle_sequence_id,
                    0
                ) asc,
                p.technical_event_fingerprint asc
        ) as purchase_instance_number,

        /*
        ============================================================
        Previous purchase by user
        ============================================================
        */

        lag(
            p.event_at
        ) over (
            partition by p.user_pseudo_id
            order by
                p.event_at asc,
                p.event_timestamp asc,
                coalesce(
                    p.event_bundle_sequence_id,
                    0
                ) asc,
                p.technical_event_fingerprint asc
        ) as previous_purchase_at,

        lag(
            p.purchase_revenue
        ) over (
            partition by p.user_pseudo_id
            order by
                p.event_at asc,
                p.event_timestamp asc,
                coalesce(
                    p.event_bundle_sequence_id,
                    0
                ) asc,
                p.technical_event_fingerprint asc
        ) as previous_purchase_revenue,

        /*
        ============================================================
        Previous purchase for same transaction
        ============================================================
        */

        lag(
            p.event_at
        ) over (
            partition by p.transaction_id_normalized
            order by
                p.event_at asc,
                p.event_timestamp asc,
                coalesce(
                    p.event_bundle_sequence_id,
                    0
                ) asc,
                p.technical_event_fingerprint asc
        ) as previous_transaction_purchase_at,

        lag(
            p.purchase_revenue
        ) over (
            partition by p.transaction_id_normalized
            order by
                p.event_at asc,
                p.event_timestamp asc,
                coalesce(
                    p.event_bundle_sequence_id,
                    0
                ) asc,
                p.technical_event_fingerprint asc
        ) as previous_transaction_purchase_revenue

    from purchases p

    left join transaction_stats ts
        on p.transaction_id_normalized
            = ts.stats_transaction_id_normalized

),

classified as (

    select

        o.*,

        /*
        ============================================================
        Transaction timing diagnostics
        ============================================================
        */

        timestamp_diff(
            o.event_at,
            o.previous_transaction_purchase_at,
            millisecond
        ) as milliseconds_since_prev_transaction_event,

        /*
        ============================================================
        Purchase classification
        ============================================================
        */

        case

            when o.transaction_id_normalized is null
                then 'missing_transaction_id'

            when o.transaction_purchase_events_raw > 1
                and o.purchase_instance_number > 1
                then 'repeated_transaction_id'

            else 'purchase'

        end as purchase_event_type,

        /*
        ============================================================
        CANONICAL PURCHASE ATTRIBUTION
        ============================================================
        */

        o.event_source
            as purchase_source,

        o.event_medium
            as purchase_medium,

        o.event_campaign
            as purchase_campaign,

        o.first_touch_source
            as purchase_first_touch_source,

        o.first_touch_medium
            as purchase_first_touch_medium,

        o.first_touch_campaign
            as purchase_first_touch_campaign,

        /*
        ============================================================
        Revenue reconciliation
        ============================================================
        */

        case

            when o.purchase_revenue is null
                and o.items_revenue is null
                then 'NO_REVENUE'

            when o.items_revenue is not null
                and o.purchase_revenue is not null
                and abs(
                    o.items_revenue
                    - o.purchase_revenue
                ) <= 0.01
                then 'MATCH'

            when o.items_revenue is null
                then 'MISSING_ITEM_REVENUE'

            when o.purchase_revenue is null
                then 'MISSING_PURCHASE_REVENUE'

            when o.items_revenue > o.purchase_revenue
                then 'ITEMS_GREATER_THAN_PURCHASE'

            when o.items_revenue < o.purchase_revenue
                then 'ITEMS_LESS_THAN_PURCHASE'

            else 'MISMATCH'

        end as revenue_reconciliation_status

    from ordered o

),

resolved as (

    select

        c.*,

        /*
        ============================================================
        Canonical order resolution
        ============================================================

        Rules:

        1. No normalized transaction ID
           -> no order.

        2. Repeated purchase event for same transaction
           -> excluded from order creation.

        3. First occurrence of valid transaction
           -> canonical order.

        Cross-user/session collisions remain diagnostics.
        They do not create additional orders.
        ============================================================
        */

        case

            when c.transaction_id_normalized is null
                then false

            when c.transaction_purchase_events_raw > 1
                and c.purchase_instance_number > 1
                then false

            else true

        end as is_order_creating_purchase

    from classified c

),

with_order_key as (

    select

        r.*,

        /*
        ============================================================
        Canonical business order key
        ============================================================

        One canonical transaction occurrence
        = one business order.

        user_pseudo_id is included to prevent accidental merging
        when the same transaction ID appears for different users.
        ============================================================
        */

        case

            when r.is_order_creating_purchase
                then to_hex(
                    md5(
                        concat(
                            coalesce(
                                r.user_pseudo_id,
                                '__null_user__'
                            ),
                            '|',
                            r.transaction_id_normalized
                        )
                    )
                )

        end as order_key

    from resolved r

),

final as (

    select

        /*
        ============================================================
        Event / Time
        ============================================================
        */

        event_date,
        event_date_dt,
        event_at,
        event_timestamp,
        event_name,
        event_previous_timestamp,

        /*
        ============================================================
        User
        ============================================================
        */

        user_pseudo_id,
        user_id,

        event_bundle_sequence_id,
        event_server_timestamp_offset,
        platform,

        has_null_user_pseudo_id,

        /*
        ============================================================
        Session
        ============================================================
        */

        ga_session_id,
        session_number,
        session_key,

        /*
        ============================================================
        Page
        ============================================================
        */

        page_location,
        page_title,
        page_referrer,

        /*
        ============================================================
        Engagement
        ============================================================
        */

        session_engaged_raw,
        engagement_time_msec,

        /*
        ============================================================
        Canonical purchase attribution
        ============================================================
        */

        purchase_source,
        purchase_medium,
        purchase_campaign,

        purchase_first_touch_source,
        purchase_first_touch_medium,
        purchase_first_touch_campaign,

        /*
        Original attribution lineage
        */

        event_source,
        event_medium,
        event_campaign,

        first_touch_source,
        first_touch_medium,
        first_touch_campaign,

        /*
        ============================================================
        Device
        ============================================================
        */

        device_category,
        os,
        browser,
        language,

        /*
        ============================================================
        Geo
        ============================================================
        */

        continent,
        country,
        region,
        city,

        /*
        ============================================================
        Ecommerce / Transaction
        ============================================================
        */

        transaction_id_raw,
        transaction_id_normalized,
        transaction_id_status,

        purchase_revenue,
        purchase_revenue_usd,

        tax_value,
        shipping_value,
        unique_items,

        /*
        ============================================================
        Item-level reconciliation
        ============================================================
        */

        items_revenue,
        items_quantity,

        item_to_purchase_revenue_diff,

        flag_item_purchase_revenue_mismatch,

        revenue_reconciliation_status,

        items,

        /*
        ============================================================
        Event identity
        ============================================================
        */

        technical_event_fingerprint,

        /*
        ============================================================
        Transaction diagnostics
        ============================================================
        */

        transaction_purchase_events_raw,
        transaction_users,
        transaction_sessions,

        first_transaction_purchase_at,

        purchase_instance_number,

        previous_purchase_at,
        previous_purchase_revenue,

        previous_transaction_purchase_at,
        previous_transaction_purchase_revenue,

        milliseconds_since_prev_transaction_event,

        /*
        ============================================================
        Classification
        ============================================================
        */

        purchase_event_type,

        case

            when transaction_id_normalized is null
                then 'MISSING_TRANSACTION_ID'

            when transaction_users > 1
                then 'CROSS_USER_COLLISION'

            when transaction_sessions > 1
                then 'CROSS_SESSION_COLLISION'

            when transaction_purchase_events_raw > 1
                and purchase_instance_number > 1
                then 'REPEATED_TRANSACTION_ID'

            when is_order_creating_purchase
                and order_key is not null
                then 'RESOLVED'

            else 'CHECK'

        end as resolution_reason,

        /*
        ============================================================
        Order
        ============================================================
        */

        order_key,

        is_order_creating_purchase

    from with_order_key

)

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
  purchase_source,
  purchase_medium,
  purchase_campaign,
  purchase_first_touch_source,
  purchase_first_touch_medium,
  purchase_first_touch_campaign,
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
  items_revenue,
  items_quantity,
  item_to_purchase_revenue_diff,
  flag_item_purchase_revenue_mismatch,
  revenue_reconciliation_status,
  items,
  technical_event_fingerprint,
  transaction_purchase_events_raw,
  transaction_users,
  transaction_sessions,
  first_transaction_purchase_at,
  purchase_instance_number,
  previous_purchase_at,
  previous_purchase_revenue,
  previous_transaction_purchase_at,
  previous_transaction_purchase_revenue,
  milliseconds_since_prev_transaction_event,
  purchase_event_type,
  resolution_reason,
  order_key,
  is_order_creating_purchase
from final
