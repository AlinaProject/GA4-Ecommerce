{{
  config(
    materialized = 'view',
    description  = 'ЄДИНЕ місце обробки purchase events. Розділяє GTM double-fire (інстант повтори, дедуплікуються) і transaction_id collision (реальні різні покупки з однаковим ID, рознесені у часі — зберігаються окремо з новим order_key).'
  )
}}

with purchase_events as (
    select *
    from {{ ref('stg_ga4__events') }}
    where is_purchase = true
      and flag_missing_txn_id = false
),

with_gaps as (
    select
        *,
        timestamp_diff(
            event_at,
            lag(event_at) over (partition by transaction_id order by event_at),
            second
        ) as seconds_since_prev_event
    from purchase_events
),

clustered as (
    select
        *,
        -- Новий кластер (= нова реальна подія/покупка) починається якщо:
        -- це перша подія АБО розрив > 3600 сек (1 година).
        -- Поріг обрано з даних: макс. розрив справжніх дублів ~8 хв,
        -- мін. розрив реально різних покупок ~5 днів. 1 година — безпечна межа.
        sum(
            case
                when seconds_since_prev_event is null
                  or seconds_since_prev_event > 3600
                then 1 else 0
            end
        ) over (
            partition by transaction_id
            order by event_at
            rows between unbounded preceding and current row
        ) as order_cluster
    from with_gaps
),

final as (
    select
        *,
        -- Якщо в transaction_id лише 1 кластер — ID лишається унікальним.
        -- Якщо кластерів >1 — реальна колізія, кожна покупка отримує свій ключ.
        case
            when max(order_cluster) over (partition by transaction_id) = 1
                then transaction_id
            else concat(transaction_id, '_c', cast(order_cluster as string))
        end as order_key

    from clustered
)

select *
from final
qualify row_number() over (
    partition by order_key
    order by event_timestamp asc
) = 1
