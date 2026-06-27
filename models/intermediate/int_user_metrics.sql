{{
  config(
    materialized = 'view',
    description  = 'Один рядок = один користувач. Lifetime-агрегати з int_sessions (НЕ перераховує revenue/purchases з fct_orders напряму — щоб не повторити transaction_id-баг).'
  )
}}
 
with sessions as (
    select * from {{ ref('int_sessions') }}
),
 
first_session as (
    select *
    from sessions
    qualify row_number() over (
        partition by user_pseudo_id order by session_start_at
    ) = 1
),
 
user_sessions as (
    select
        user_pseudo_id,
        count(distinct session_id)              as total_sessions,
        sum(pageviews)                          as total_pageviews,
        avg(session_duration_min)               as avg_session_duration,
        min(session_start_at)                   as first_seen,
        max(session_end_at)                     as last_seen,
        date_diff(max(session_date), min(session_date), day) as active_days,
        sum(session_revenue)                    as total_revenue,
        sum(transaction_count)                  as purchases,
        countif(converted)                      as converting_sessions,
        round(
            sum(session_revenue) / nullif(sum(transaction_count), 0), 2
        )                                        as avg_order_value
    from sessions
    group by 1
)
 
-- Примітка: customer_segment свідомо НЕ додано.
-- Датасет покриває лише 3 місяці — недостатньо часу щоб користувачі накопичили повторні покупки, 
-- "loyal"-сегмент був би статистично нерепрезентативним (одиничні випадки видавали б за тренд).
 
select
 
    u.user_pseudo_id,
    u.total_sessions,
    u.total_pageviews,
    u.avg_session_duration,
    u.first_seen,
    u.last_seen,
    u.active_days,
    u.total_revenue,
    u.purchases,
    u.converting_sessions,
    u.avg_order_value,
 
    f.channel_group,
    f.source,
    f.medium,
    f.country,
    f.city,
    f.device_category,
    f.os,
    f.browser
 
from user_sessions u
left join first_session f using (user_pseudo_id)
