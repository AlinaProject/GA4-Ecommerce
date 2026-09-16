{{
    config(
        materialized = 'view',
        description = 'One row per item in a canonical business order. Items inherit attribution, device and geo from the canonical purchase event that created the order.'
    )
}}

with canonical_purchases as (

    select

        order_key,

        transaction_id_normalized,

        event_at,
        event_date_dt,

        user_pseudo_id,
        ga_session_id,
        session_key,

        event_source,
        event_medium,
        event_campaign,

        first_touch_source,
        first_touch_medium,
        first_touch_campaign,

        device_category,
        os,
        browser,

        continent,
        country,
        region,
        city,

        items,

        purchase_revenue,
        purchase_revenue_usd,

        technical_event_fingerprint

    from {{ ref('int_purchase_events_resolved') }}

    where is_order_creating_purchase = true

      and order_key is not null

      and transaction_id_normalized is not null

),

purchase_items as (

    select

        /*
        ============================================================
        Grain
        ============================================================

        One row = one item in one canonical business order.

        order_key + item_offset identifies the item occurrence.
        */

        to_hex(
            md5(
                concat(
                    p.order_key,
                    '|item_offset:',
                    cast(item_offset as string)
                )
            )
        ) as order_item_key,

        p.order_key,

        p.transaction_id_normalized,

        /*
        User / session
        */

        p.session_key as session_id,

        p.user_pseudo_id,

        p.ga_session_id,

        /*
        Dates
        */

        p.event_at as purchased_at,

        p.event_date_dt as purchase_date,

        /*
        ============================================================
        Product key
        ============================================================

        Product key belongs here, because this is where the raw
        GA4 item is transformed into a canonical product reference.

        Normalize item_id before hashing.

        If item_id is missing, product_key remains NULL.
        We deliberately do NOT create a fake "null product" key.
        */

        case
            when nullif(
                trim(cast(item.item_id as string)),
                ''
            ) is not null

            then to_hex(
                md5(
                    trim(
                        cast(item.item_id as string)
                    )
                )
            )
        end as product_key,

        nullif(
            trim(cast(item.item_id as string)),
            ''
        ) as product_id,

        nullif(
            trim(item.item_name),
            ''
        ) as product_name,

        nullif(
            trim(item.item_brand),
            '(not set)'
        ) as item_brand,

        nullif(
            trim(item.item_variant),
            '(not set)'
        ) as item_variant,

        item.item_category as item_category_raw,

        split(
            trim(item.item_category, '/'),
            '/'
        )[safe_offset(0)] as category_l1,

        split(
            trim(item.item_category, '/'),
            '/'
        )[safe_offset(1)] as category_l2,

        split(
            trim(item.item_category, '/'),
            '/'
        )[safe_offset(2)] as category_l3,

        /*
        ============================================================
        Measures
        ============================================================
        */

        safe_cast(
            item.price as numeric
        ) as item_price,

        safe_cast(
            item.quantity as numeric
        ) as item_quantity,

        safe_cast(
            item.item_revenue as numeric
        ) as item_revenue,

        /*
        ============================================================
        Promotions
        ============================================================
        */

        nullif(
            trim(item.promotion_id),
            '(not set)'
        ) as promotion_id,

        nullif(
            trim(item.promotion_name),
            '(not set)'
        ) as promotion_name,

        item.item_list_index as list_position,

        item_offset,

        /*
        ============================================================
        Canonical purchase attribution
        ============================================================

        These fields MUST be identical in semantic meaning to
        fct_orders attribution.

        */

        p.event_source as purchase_source,

        p.event_medium as purchase_medium,

        p.event_campaign as purchase_campaign,

        p.first_touch_source,

        p.first_touch_medium,

        p.first_touch_campaign,

        /*
        ============================================================
        Product-level dimension attributes
        ============================================================
        */

        p.device_category,

        p.os,

        p.browser,

        p.continent,

        p.country,

        p.region,

        p.city,

        /*
        ============================================================
        Data quality
        ============================================================
        */

        item.item_id is null
            or trim(cast(item.item_id as string)) = ''
            as flag_missing_product_id,

        item.item_name is null
            or trim(item.item_name) = ''
            as flag_missing_product_name,

        (
            item.price is null
            or safe_cast(item.price as numeric) <= 0
        ) as flag_invalid_price,

        item.quantity is null
            as flag_null_quantity,

        item.item_revenue is null
            as flag_null_item_revenue,

        /*
        Revenue integrity at item level.
        */

        item.item_revenue is not null
        and safe_cast(item.item_revenue as numeric) < 0
            as flag_negative_item_revenue

    from canonical_purchases p

    cross join unnest(p.items)
        as item with offset as item_offset

)

select 
  order_item_key,
  order_key,
  transaction_id_normalized,
  session_key as session_id,
  user_pseudo_id,
  ga_session_id,
  purchased_at,
  purchase_date,
  product_key,
  product_id,
  product_name,
  item_brand,
  item_variant,
  item_category_raw,
  category_l1,
  category_l2,
  category_l3,
  item_price,
  item_quantity,
  item_revenue,
  promotion_id,
  promotion_name,
  list_position,
  item_offset,
  purchase_source,
  purchase_medium,
  purchase_campaign,
  first_touch_source,
  first_touch_medium,
  first_touch_campaign,
  device_category,
  os,
  browser,
  continent,
  ountry,
  region,
  city,
  flag_missing_product_id,
  flag_missing_product_name,
  flag_invalid_price,
  flag_null_quantity,
  flag_null_item_revenue,
  flag_negative_item_revenue
from purchase_items
