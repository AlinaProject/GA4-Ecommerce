{{ config(
    materialized = 'table',
    cluster_by = [
        'audit_area',
        'issue_type'
    ],
    description = 'Structural data quality audit across sessions, orders and order items.'
) }}

with session_issues as (

    select

        session_date as audit_date,

        'SESSION' as audit_area,

        issue_type,

        'HIGH' as severity,

        session_id as entity_key,

        cast(null as string) as transaction_id_normalized,

        cast(null as string) as order_key,

        1 as affected_rows,

        session_revenue as affected_revenue

    from {{ ref('fct_sessions') }}

    cross join unnest([

        if(
            session_id is null,
            'NULL_SESSION_ID',
            null
        ),

        if(
            ga_session_id is null,
            'NULL_GA_SESSION_ID',
            null
        ),

        if(
            total_events <= 0,
            'INVALID_EVENT_COUNT',
            null
        ),

        if(
            session_duration_min < 0,
            'NEGATIVE_DURATION',
            null
        ),

        if(
            session_duration_min > 1440,
            'IMPOSSIBLE_DURATION',
            null
        )

    ]) as issue_type

    where issue_type is not null

),

order_issues as (

    select

        order_date as audit_date,

        'ORDER' as audit_area,

        issue_type,

        'HIGH' as severity,

        order_key as entity_key,

        transaction_id_normalized,

        order_key,

        1 as affected_rows,

        purchase_revenue as affected_revenue

    from {{ ref('fct_orders') }}

    cross join unnest([

        if(
            order_key is null,
            'NULL_ORDER_KEY',
            null
        ),

        if(
            transaction_id_normalized is null,
            'NULL_TRANSACTION_ID',
            null
        ),

        if(
            session_id is null,
            'NULL_SESSION_ID',
            null
        ),

        if(
            user_pseudo_id is null,
            'NULL_USER',
            null
        ),

        if(
            purchase_revenue is null,
            'NULL_REVENUE',
            null
        ),

        if(
            purchase_revenue < 0,
            'NEGATIVE_REVENUE',
            null
        )

    ]) as issue_type

    where issue_type is not null

),

order_item_issues as (

    select

        purchase_date as audit_date,

        'ORDER_ITEM' as audit_area,

        issue_type,

        'HIGH' as severity,

        order_item_key as entity_key,

        cast(null as string) as transaction_id_normalized,

        order_key,

        1 as affected_rows,

        item_revenue as affected_revenue

    from {{ ref('fct_order_items') }}

    cross join unnest([

        if(
            order_item_key is null,
            'NULL_ORDER_ITEM_KEY',
            null
        ),

        if(
            order_key is null,
            'NULL_ORDER_KEY',
            null
        ),

        if(
            product_key is null,
            'NULL_PRODUCT_KEY',
            null
        ),

        if(
            item_quantity is null,
            'NULL_QUANTITY',
            null
        ),

        if(
            item_quantity < 0,
            'NEGATIVE_QUANTITY',
            null
        ),

        if(
            item_revenue is null,
            'NULL_ITEM_REVENUE',
            null
        ),

        if(
            item_price is null
            or item_price <= 0,
            'INVALID_ITEM_PRICE',
            null
        )

    ]) as issue_type

    where issue_type is not null

)

select

    current_timestamp() as audit_at,

    audit_date,
    audit_area,
    issue_type,
    severity,

    entity_key,

    transaction_id_normalized,
    order_key,

    affected_rows,
    affected_revenue

from session_issues

union all

select

    current_timestamp() as audit_at,

    audit_date,
    audit_area,
    issue_type,
    severity,

    entity_key,

    transaction_id_normalized,
    order_key,

    affected_rows,
    affected_revenue

from order_issues

union all

select

    current_timestamp() as audit_at,

    audit_date,
    audit_area,
    issue_type,
    severity,

    entity_key,

    transaction_id_normalized,
    order_key,

    affected_rows,
    affected_revenue

from order_item_issues
