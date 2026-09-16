{{
config(
materialized = 'table',

    cluster_by = [
        'reconciliation_area',
        'reconciliation_status'
    ],
    description = 'Reconciliation between canonical purchase resolution, fct_orders, fct_order_items and fct_sessions. Separates order-resolution integrity from item-level revenue reconciliation.'
)
}}

with purchase_resolution as (

    select

        countif(
            is_order_creating_purchase
        ) as resolved_purchase_events,

        count(
            distinct if(
                is_order_creating_purchase,
                order_key,
                null
            )
        ) as resolved_orders,

        sum(
            case
                when is_order_creating_purchase
                    then coalesce(
                        purchase_revenue,
                        0
                    )
                else 0
            end
        ) as resolved_order_revenue,

        sum(
            case
                when is_order_creating_purchase
                    then coalesce(
                        items_revenue,
                        0
                    )
                else 0
            end
        ) as resolved_item_revenue,

        sum(
            case
                when is_order_creating_purchase
                    then coalesce(
                        item_to_purchase_revenue_diff,
                        0
                    )
                else 0
            end
        ) as resolved_item_revenue_difference

    from {{ ref('int_purchase_events_resolved') }}

),

orders as (

    select

        count(*) as order_rows,

        count(
            distinct order_key
        ) as distinct_orders,

        sum(
            coalesce(
                purchase_revenue,
                0
            )
        ) as order_revenue

    from {{ ref('fct_orders') }}

),

order_items as (

    select

        count(*) as order_item_rows,

        count(
            distinct order_key
        ) as orders_with_items,

        sum(
            coalesce(
                item_revenue,
                0
            )
        ) as item_revenue

    from {{ ref('fct_order_items') }}

),

sessions as (

    select

        sum(
            coalesce(
                transaction_count,
                0
            )
        ) as session_order_count,

        sum(
            coalesce(
                session_revenue,
                0
            )
        ) as session_revenue

    from {{ ref('fct_sessions') }}

),

checks as (

    -- ========================================================
    -- 1. RESOLUTION → ORDERS COUNT
    -- ========================================================

    select

        'RESOLUTION_TO_ORDERS_COUNT'
            as reconciliation_area,

        r.resolved_orders
            as source_value,

        o.distinct_orders
            as target_value,

        r.resolved_orders
            - o.distinct_orders
            as difference,

        case

            when r.resolved_orders
                = o.distinct_orders
                then 'PASS'

            else 'FAIL'

        end as reconciliation_status

    from purchase_resolution r
    cross join orders o


    union all


    -- ========================================================
    -- 2. RESOLUTION → ORDERS REVENUE
    -- ========================================================

    select

        'RESOLUTION_TO_ORDERS_REVENUE'
            as reconciliation_area,

        r.resolved_order_revenue
            as source_value,

        o.order_revenue
            as target_value,

        r.resolved_order_revenue
            - o.order_revenue
            as difference,

        case

            when abs(
                r.resolved_order_revenue
                - o.order_revenue
            ) <= 0.01

                then 'PASS'

            else 'FAIL'

        end as reconciliation_status

    from purchase_resolution r
    cross join orders o


    union all


    -- ========================================================
    -- 3. ORDERS → ITEMS REVENUE
    --
    -- Diagnostic.
    --
    -- fct_orders = order-level revenue
    -- fct_order_items = item-level revenue
    -- ========================================================

    select

        'ORDERS_TO_ITEMS_REVENUE'
            as reconciliation_area,

        o.order_revenue
            as source_value,

        i.item_revenue
            as target_value,

        o.order_revenue
            - i.item_revenue
            as difference,

        case

            when abs(
                o.order_revenue
                - i.item_revenue
            ) <= 0.01

                then 'PASS'

            else 'REVIEW'

        end as reconciliation_status

    from orders o
    cross join order_items i


    union all


    -- ========================================================
    -- 4. RESOLVED PURCHASE → RESOLVED ITEM REVENUE
    --
    -- Direct check against canonical intermediate.
    -- ========================================================

    select

        'RESOLUTION_ORDER_TO_ITEM_REVENUE'
            as reconciliation_area,

        r.resolved_order_revenue
            as source_value,

        r.resolved_item_revenue
            as target_value,

        r.resolved_order_revenue
            - r.resolved_item_revenue
            as difference,

        case

            when abs(
                r.resolved_order_revenue
                - r.resolved_item_revenue
            ) <= 0.01

                then 'PASS'

            else 'REVIEW'

        end as reconciliation_status

    from purchase_resolution r


    union all


    -- ========================================================
    -- 5. ORDERS → SESSIONS COUNT
    -- ========================================================

    select

        'ORDERS_TO_SESSIONS_COUNT'
            as reconciliation_area,

        o.distinct_orders
            as source_value,

        s.session_order_count
            as target_value,

        o.distinct_orders
            - s.session_order_count
            as difference,

        case

            when o.distinct_orders
                = s.session_order_count

                then 'PASS'

            else 'FAIL'

        end as reconciliation_status

    from orders o
    cross join sessions s


    union all


    -- ========================================================
    -- 6. ORDERS → SESSIONS REVENUE
    -- ========================================================

    select

        'ORDERS_TO_SESSIONS_REVENUE'
            as reconciliation_area,

        o.order_revenue
            as source_value,

        s.session_revenue
            as target_value,

        o.order_revenue
            - s.session_revenue
            as difference,

        case

            when abs(
                o.order_revenue
                - s.session_revenue
            ) <= 0.01

                then 'PASS'

            else 'FAIL'

        end as reconciliation_status

    from orders o
    cross join sessions s

)

select

    current_timestamp() as audit_at,

    reconciliation_area,

    source_value,
    target_value,
    difference,

    reconciliation_status

from checks
