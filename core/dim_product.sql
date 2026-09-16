{{ config(
    materialized = 'table',
    cluster_by = ['category_l1', 'item_brand']
) }}

with products as (

    select
        product_key,
        product_id,
        product_name,
        item_brand,
        item_variant,
        item_category_raw as item_category,
        category_l1,
        category_l2,
        category_l3,
        purchased_at

    from {{ ref('int_purchase_items') }}

    where product_id is not null

),

deduplicated as (

    select
        product_key,
        product_id,
        product_name,
        item_brand,
        item_variant,
        item_category,
        category_l1,
        category_l2,
        category_l3,
        purchased_at

    from products

    qualify row_number() over (
        partition by product_key
        order by
            purchased_at desc,
            product_name desc,
            item_brand desc,
            item_variant desc
    ) = 1

)

select
    product_key,
    product_id,
    product_name,
    item_brand,
    item_variant,
    item_category,
    category_l1,
    category_l2,
    category_l3

from deduplicated
