{{
  config(
    materialized = 'view',
    description  = 'Дедупліковані транзакції + UNNEST items. Один рядок = один товар.'
  )
}}

with raw_purchases as (
    select *
    from {{ ref('stg_ga4__events') }}
    where is_purchase = true
      and flag_missing_txn_id = false
),

-- Дедуплікація: залишаємо тільки першу подію кожної транзакції
-- Причина: GTM double-fire, page reload після purchase
deduped as (
    select *
    from raw_purchases
    qualify row_number() over (
        partition by transaction_id
        order by event_timestamp asc
    ) = 1
),

-- UNNEST items: 1 транзакція × N товарів = N рядків
purchase_items as (
    select

        -- Transaction identifiers
        p.transaction_id,
        p.user_pseudo_id,
        p.ga_session_id,
        concat(p.user_pseudo_id, '-',
               cast(p.ga_session_id as string))     as session_id,
        p.event_at                                   as purchased_at,
        p.event_date_dt                              as purchase_date,

        -- Transaction metrics
        p.purchase_revenue                           as transaction_revenue,
        p.tax_value,
        p.shipping_value,
        p.unique_items                               as transaction_item_count,

        -- Attribution
        p.channel_group,
        p.session_source                             as source,
        p.session_medium                             as medium,
        p.device_category,
        p.country,

        -- Item fields (після UNNEST)
        item.item_id,
        item.item_name,
        nullif(item.item_brand, '(not set)')         as item_brand,
        nullif(item.item_variant, '(not set)')       as item_variant,

        -- Category parsing: "Home/Apparel/Men's/T-Shirts/" → рівні
        item.item_category                           as item_category_raw,
        split(trim(item.item_category, '/'), '/')[safe_offset(0)] as category_l1,
        split(trim(item.item_category, '/'), '/')[safe_offset(1)] as category_l2,
        split(trim(item.item_category, '/'), '/')[safe_offset(2)] as category_l3,

        -- Price: приходить як FLOAT64 в публічному датасеті
        -- Але safe_cast для безпеки
        safe_cast(item.price as float64)             as item_price,
        item.quantity                                as item_quantity,
        item.item_revenue                            as item_revenue,

        -- Promotions
        nullif(item.promotion_id, '(not set)')       as promotion_id,
        nullif(item.promotion_name, '(not set)')     as promotion_name,
        item.item_list_index                         as list_position

    from deduped p,
    unnest(items) as item
),

final as (
    select
        *,
        row_number() over (
            partition by transaction_id
            order by list_position nulls last, item_id
        )                                            as item_rank,

        -- DQ flags
        item_price <= 0 or item_price is null        as flag_invalid_price,
        item_quantity is null                        as flag_null_quantity,
        item_revenue is null                         as flag_null_revenue,

        row_number() over (
            partition by transaction_id
            order by list_position nulls last, item_id
        ) = 1                                        as is_primary_item

    from purchase_items
)

select * from final