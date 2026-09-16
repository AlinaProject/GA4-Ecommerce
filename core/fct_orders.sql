{{ config(
    materialized = 'table',
    description = 'One row = one resolved business order. Source of truth for order revenue.',
    cluster_by = [
    "user_pseudo_id",
    "transaction_id_normalized"]  
) }}

select
    cast(order_key as string) as order_key,

    transaction_id_normalized,

    cast(event_date_dt as date) as order_date,
    event_at as order_at,

    -- 2. КРИТИЧНО: Захист полів кластеризації від NULL / некоректних типів
    cast(user_pseudo_id as string) as user_pseudo_id,
    cast(session_key as string) as session_id,


    ga_session_id,

    /*
    Star-schema foreign keys.
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
        'event_source',
        'event_medium',
        'event_campaign'
    ]) }} as attribution_key,

    {{ generate_key([
        'first_touch_source',
        'first_touch_medium',
        'first_touch_campaign'
    ]) }} as first_touch_attribution_key,

    /*
    Revenue.
    */

    purchase_revenue,
    purchase_revenue_usd,

    tax_value,
    shipping_value,
    unique_items,

    /*
    Resolution lineage.
    */

    purchase_event_type,
    resolution_reason,
    purchase_instance_number,

    transaction_purchase_events_raw,
    transaction_users,
    transaction_sessions,

    technical_event_fingerprint,

    event_source,
    event_medium,
    event_campaign,

    first_touch_source,
    first_touch_medium,
    first_touch_campaign

from {{ ref('int_purchase_events_resolved') }} 
where is_order_creating_purchase = true and order_key is not null and transaction_id_normalized is not null
