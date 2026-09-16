with orders as (

    select

        order_key,
        transaction_id_normalized,

        order_date,
        order_at,

        user_pseudo_id,
        session_id,

        purchase_revenue,
        purchase_revenue_usd,

        purchase_event_type,
        resolution_reason,
        purchase_instance_number,

        technical_event_fingerprint

    from {{ ref('fct_orders') }}

),

items as (

    select

        order_key,

        sum(
            coalesce(
                item_revenue,
                0
            )
        ) as item_revenue,

        count(*) as item_rows,

        countif(
            item_revenue is null
        ) as null_item_revenue_rows,

        countif(
            product_id is null
        ) as missing_product_rows

    from {{ ref('fct_order_items') }}

    group by 1

),

final as (

    select

        o.order_key,
        o.transaction_id_normalized,

        o.order_date,
        o.order_at,

        o.user_pseudo_id,
        o.session_id,

        o.purchase_revenue,
        o.purchase_revenue_usd,

        coalesce(
            i.item_revenue,
            0
        ) as item_revenue,

        o.purchase_revenue
            - coalesce(
                i.item_revenue,
                0
            ) as revenue_difference,

        coalesce(
            i.item_rows,
            0
        ) as item_rows,

        coalesce(
            i.null_item_revenue_rows,
            0
        ) as null_item_revenue_rows,

        coalesce(
            i.missing_product_rows,
            0
        ) as missing_product_rows,

        o.purchase_event_type,
        o.resolution_reason,
        o.purchase_instance_number,

        o.technical_event_fingerprint,

        case

            when i.order_key is null
                then 'NO_ITEMS'

            when abs(
                o.purchase_revenue
                - coalesce(
                    i.item_revenue,
                    0
                )
            ) <= 0.01
                then 'MATCH'

            when o.purchase_revenue
                > coalesce(
                    i.item_revenue,
                    0
                )
                then 'ORDER_REVENUE_GT_ITEMS'

            when o.purchase_revenue
                < coalesce(
                    i.item_revenue,
                    0
                )
                then 'ITEM_REVENUE_GT_ORDER'

            else 'CHECK'

        end as reconciliation_status

    from orders o

    left join items i
        on o.order_key = i.order_key

)

select *

from final
