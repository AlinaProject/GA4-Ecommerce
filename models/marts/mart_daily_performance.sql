{{ config(materialized='table') }}

with sessions as (

    select *
    from {{ ref('int_sessions') }}

)

select

    session_date,
    channel_group,
    source,
    medium,
    country,
    city,
    device_category,
    os,
    browser,
    
    count(*) as sessions,

    count(distinct user_pseudo_id) as users,

    sum(transaction_count) as orders,

    sum(session_revenue) as revenue,

    countif(converted) as converting_sessions,
    countif(is_new_user) as new_users,

    round(
        countif(converted)
        / nullif(count(*),0), 4
    ) as session_cvr,

    round(sum(session_revenue)/ nullif(sum(transaction_count),0),2) as aov,

    round(
        sum(session_revenue)
        / nullif(count(*),0),
        2
    ) as revenue_per_session,

    round(
        sum(session_revenue) / nullif(count(distinct user_pseudo_id), 0), 2
    ) as arpu,
    
    round(countif(is_new_user) / nullif(count(*),0), 4) as new_user_share

from sessions

group by all