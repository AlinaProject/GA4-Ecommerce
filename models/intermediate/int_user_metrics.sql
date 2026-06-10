{{
    config(
        materialized='view'
    )
}}

with sessions as (

    select *
    from {{ ref('stg_ga4__sessions') }}

),

purchases as (

    select *
    from {{ ref('stg_ga4__purchases') }}

),

user_sessions as (

    select

        user_pseudo_id,

        count(distinct session_id) as total_sessions,

        sum(pageviews) as total_pageviews,

        avg(session_duration_min)
            as avg_session_duration,

        min(session_start_at)
            as first_seen,

        max(session_end_at)
            as last_seen,

        sum(
            case
                when converted then 1
                else 0
            end
        ) as converting_sessions

    from sessions
    group by 1

),

user_revenue as (

    select

        user_pseudo_id,

        count(distinct transaction_id)
            as purchases,

        sum(item_revenue)
            as revenue

    from {{ ref('stg_ga4__purchases') }}

    group by 1

)

select

    s.user_pseudo_id,

    s.total_sessions,

    s.total_pageviews,

    s.avg_session_duration,

    s.first_seen,

    s.last_seen,

    timestamp_diff(
        s.last_seen,
        s.first_seen,
        day
    ) as active_days,

    coalesce(r.purchases,0)
        as purchases,

    coalesce(r.revenue,0)
        as revenue,

    case
        when coalesce(r.purchases,0)=0
            then 'non_buyer'

        when coalesce(r.purchases,0)=1
            then 'one_time'

        when coalesce(r.purchases,0)<=5
            then 'repeat'

        else 'loyal'
    end as customer_segment

from user_sessions s

left join user_revenue r
using(user_pseudo_id)