{{ config(materialized='table') }}

with sessions as (

    select *
    from {{ ref('stg_ga4__sessions') }}

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

    sum(transaction_count) as transactions,

    sum(session_revenue) as revenue,

    countif(converted) as converting_sessions,

    round(
        countif(converted)
        / nullif(count(*),0),
        4
    ) as session_cvr,

    round(
        sum(session_revenue)
        / nullif(sum(transaction_count),0),
        2
    ) as aov,

    round(
        sum(session_revenue)
        / nullif(count(*),0),
        2
    ) as revenue_per_session,

    countif(is_new_user) as new_users,
    round(countif(is_new_user) / nullif(count(*),0), 4) as new_user_share

from sessions

group by all
