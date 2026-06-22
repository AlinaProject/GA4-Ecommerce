{{ config(
    materialized='table',
    description  = 'Перша сторінка кожної сесії + конверсія. Аналіз вхідних точок трафіку.'

) }}

with first_page as (

    select

        concat(
            user_pseudo_id,
            '-',
            cast(ga_session_id as string)
        ) as session_id,

        event_date_dt as session_date,

        page_location,

        page_title,

        channel_group,

        session_source as source,
        session_medium as medium,

        country,
        city,

        device_category,
        os,
        browser,
        language,

        row_number() over (
            partition by user_pseudo_id, ga_session_id
            order by event_timestamp
        ) as rn

    from {{ ref('stg_ga4__events') }}
    where page_location is not null

),

landing_pages as (

    select *
    from first_page
    where rn = 1

),

session_metrics as (

    select
        session_id,
        converted,
        session_revenue,
        transaction_count
    from {{ ref('int_sessions') }}
)

select

    l.session_date,

    l.page_location,
    l.page_title,

    l.channel_group,
    l.source,
    l.medium,

    l.country,
    l.city,

    l.device_category,
    l.os,
    l.browser,
    l.language,

    count(*) as sessions,

    countif(converted) as conversions,

    sum(transaction_count) as transactions,

    sum(session_revenue) as revenue,

    round(
        countif(converted)
        / nullif(count(*),0),
        4
    ) as cvr

from landing_pages l

left join session_metrics s
    using(session_id)

group by all