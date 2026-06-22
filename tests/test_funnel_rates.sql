select *
from {{ ref('mart_funnel') }}
where item_to_cart_rate > 1
   or cart_to_checkout_rate > 1
   or payment_to_purchase_rate > 1
