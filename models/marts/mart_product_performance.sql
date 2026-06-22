{{ config(materialized='table') }}

with purchases as (

    select *
    from {{ ref('fct_order_items') }}

)

select

    purchase_date,
    item_id,
    item_name,
    item_brand,
    category_l1,
    category_l2,
    category_l3,
    country,
    device_category,
    source,
    medium,

    count(distinct order_key) as transactions,

    sum(item_quantity) as units_sold,

    round(sum(item_revenue),2) as revenue,

    round(avg(item_price),2) as avg_price

from purchases

group by all
