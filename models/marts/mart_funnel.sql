{{
  config(
    materialized = 'table',
    description  = 'Повна воронка конверсії по днях, усі 5 переходів — включно з checkout→shipping і shipping→payment (найбільший drop-off за EDA, 54%).'
  )
}}

select

    session_date,

    count(*)                                                  as sessions,
    countif(reached_item_view = 1)                            as item_views,
    countif(reached_cart = 1)                                 as carts,
    countif(reached_checkout = 1)                              as checkouts,
    countif(reached_shipping = 1)                              as shippings,
    countif(reached_payment = 1)                               as payments,
    countif(reached_purchase = 1)                              as purchases,

    round(
        countif(reached_item_view = 1 and reached_cart = 1)
        / nullif(countif(reached_item_view = 1), 0), 4
    )                                                          as item_to_cart_rate,

    round(
        countif(reached_cart = 1 and reached_checkout = 1)
        / nullif(countif(reached_cart = 1), 0), 4
    )                                                          as cart_to_checkout_rate,

    round(
        countif(reached_checkout = 1 and reached_shipping = 1)
        / nullif(countif(reached_checkout = 1), 0), 4
    )                                                          as checkout_to_shipping_rate,

    round(
        countif(reached_shipping = 1 and reached_payment = 1)
        / nullif(countif(reached_shipping = 1), 0), 4
    )                                                          as shipping_to_payment_rate,

    round(
        countif(reached_payment = 1 and reached_purchase = 1)
        / nullif(countif(reached_payment = 1), 0), 4
    )                                                          as payment_to_purchase_rate

from {{ ref('int_sessions') }}
group by 1