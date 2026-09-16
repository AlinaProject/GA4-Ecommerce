{{ config(
    materialized = 'table'
) }}

with sessions as (

    select

        session_date as date_key,

        count(*) as sessions,

        countif(is_impossible_duration)
            as impossible_duration_sessions,

        countif(is_high_event_session)
            as suspicious_sessions,

        countif(has_gdpr_deleted)
            as gdpr_deleted_sessions,

        countif(has_self_referral)
            as self_referral_sessions,

        countif(is_single_event_or_zero_duration)
            as single_event_sessions,

        countif(is_clean_session)
            as clean_sessions

    from {{ ref('fct_sessions') }}

    group by 1

),

order_items as (

    select

        purchase_date as date_key,

        count(*) as order_item_rows,

        countif(flag_missing_product_id)
            as missing_product_id_rows,

        countif(flag_missing_product_name)
            as missing_product_name_rows,

        countif(flag_invalid_price)
            as invalid_price_rows,

        countif(flag_null_quantity)
            as null_quantity_rows,

        countif(flag_null_item_revenue)
            as null_item_revenue_rows

    from {{ ref('fct_order_items') }}

    group by 1

),

orders as (

    select

        order_date as date_key,

        count(*) as order_rows,

        countif(order_key is null)
            as missing_order_key_rows,

        countif(transaction_id_normalized is null)
            as missing_transaction_id_rows,

        countif(session_id is null)
            as missing_session_rows,

        countif(
            purchase_revenue is null
        ) as null_order_revenue_rows

    from {{ ref('fct_orders') }}

    group by 1

),

purchase_resolution as (

    select

        event_date_dt as date_key,

        count(*) as purchase_event_rows,

        countif(
            transaction_id_normalized is null
        ) as missing_transaction_id_rows,

        countif(
            is_order_creating_purchase
        ) as resolved_purchase_events,

        countif(
            not is_order_creating_purchase
        ) as excluded_purchase_events,

        countif(
            is_order_creating_purchase
            and order_key is null
        ) as resolution_errors,

        countif(
            flag_item_purchase_revenue_mismatch
        ) as purchase_revenue_mismatch_events

    from {{ ref('int_purchase_events_resolved') }}

    group by 1

)

select

    c.date_key,

    c.year,
    c.quarter,
    c.month,
    c.month_name,
    c.year_month,
    c.week_start,
    c.month_start,
    c.is_weekend,

    -- ========================================================
    -- Sessions
    -- ========================================================

    coalesce(
        s.sessions,
        0
    ) as sessions,

    coalesce(
        s.impossible_duration_sessions,
        0
    ) as impossible_duration_sessions,

    coalesce(
        s.suspicious_sessions,
        0
    ) as suspicious_sessions,

    coalesce(
        s.gdpr_deleted_sessions,
        0
    ) as gdpr_deleted_sessions,

    coalesce(
        s.self_referral_sessions,
        0
    ) as self_referral_sessions,

    coalesce(
        s.single_event_sessions,
        0
    ) as single_event_sessions,

    coalesce(
        s.clean_sessions,
        0
    ) as clean_sessions,

    safe_divide(
        coalesce(s.clean_sessions, 0),
        nullif(s.sessions, 0)
    ) as clean_session_rate,

    -- ========================================================
    -- Order items
    -- ========================================================

    coalesce(
        i.order_item_rows,
        0
    ) as order_item_rows,

    coalesce(
        i.missing_product_id_rows,
        0
    ) as missing_product_id_rows,

    coalesce(
        i.missing_product_name_rows,
        0
    ) as missing_product_name_rows,

    coalesce(
        i.invalid_price_rows,
        0
    ) as invalid_price_rows,

    coalesce(
        i.null_quantity_rows,
        0
    ) as null_quantity_rows,

    coalesce(
        i.null_item_revenue_rows,
        0
    ) as null_item_revenue_rows,

    -- ========================================================
    -- Orders
    -- ========================================================

    coalesce(
        o.order_rows,
        0
    ) as order_rows,

    coalesce(
        o.missing_order_key_rows,
        0
    ) as missing_order_key_rows,

    coalesce(
        o.missing_transaction_id_rows,
        0
    ) as missing_transaction_id_rows,

    coalesce(
        o.missing_session_rows,
        0
    ) as missing_session_rows,

    coalesce(
        o.null_order_revenue_rows,
        0
    ) as null_order_revenue_rows,

    -- ========================================================
    -- Purchase resolution
    -- Source of truth for purchase-event DQ.
    -- ========================================================

    coalesce(
        p.purchase_event_rows,
        0
    ) as purchase_event_rows,

    coalesce(
        p.missing_transaction_id_rows,
        0
    ) as purchase_missing_transaction_id_rows,

    coalesce(
        p.resolved_purchase_events,
        0
    ) as resolved_purchase_events,

    coalesce(
        p.excluded_purchase_events,
        0
    ) as excluded_purchase_events,

    coalesce(
        p.resolution_errors,
        0
    ) as resolution_errors,

    coalesce(
        p.purchase_revenue_mismatch_events,
        0
    ) as purchase_revenue_mismatch_events

from {{ ref('dim_calendar') }} c

left join sessions s
    on c.date_key = s.date_key

left join order_items i
    on c.date_key = i.date_key

left join orders o
    on c.date_key = o.date_key

left join purchase_resolution p
    on c.date_key = p.date_key
