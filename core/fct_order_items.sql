{{ config(
    materialized = 'table',
    description = 'Grain: 1 product in 1 order.',
    cluster_by = ['order_key', 'product_key']
) }}

select

    -- Keys
    order_item_key,
    order_key,
    transaction_id_normalized,
    product_key,

    -- User / session
    session_id,
    user_pseudo_id,
    ga_session_id,

    -- Dates
    purchased_at,
    purchase_date,

    -- Product reference
    product_id,

    -- Measures
    item_price,
    item_quantity,
    item_revenue,

    -- Promotions
    promotion_id,
    promotion_name,

    -- Item metadata
    list_position,
    item_offset,

    -- Data quality
    flag_missing_product_id,
    flag_missing_product_name,
    flag_invalid_price,
    flag_null_quantity,
    flag_null_item_revenue,
    flag_negative_item_revenue

from {{ ref('int_purchase_items') }}
