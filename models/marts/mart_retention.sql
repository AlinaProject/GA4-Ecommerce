{{ config(materialized='table') }}

with first_session as (

    select

        user_pseudo_id,

        session_date as first_session_date,

        date_trunc(session_date, month) as cohort_month,

        coalesce(country, '(unknown)')         as country,
        coalesce(device_category, '(unknown)') as device_category,
        coalesce(channel_group, '(unknown)')   as channel_group,
        coalesce(source, '(unknown)')          as source,
        coalesce(medium, '(unknown)')          as medium,
        coalesce(browser, '(unknown)')         as browser,
        coalesce(os, '(unknown)')              as os,

    from {{ ref('int_sessions') }}

    qualify row_number() over (
        partition by user_pseudo_id
        order by session_start_at
    ) = 1

),

user_activity as (

    select
        s.user_pseudo_id,
        f.cohort_month,
        f.country,
        f.device_category,
        f.channel_group,
        f.source,
        f.medium,
        f.browser,
        f.os,

        date_diff(
            date_trunc(s.session_date, month),
            f.cohort_month,
            month
        ) as month_number

    from {{ ref('int_sessions') }} s

    inner join first_session f
        on s.user_pseudo_id = f.user_pseudo_id

),

retention as (

    select
        cohort_month,
        month_number,
        country,
        device_category,
        channel_group,
        source,
        medium,
        browser,
        os,

        count(distinct user_pseudo_id) as active_users

    from user_activity

    group by all

),

cohort_sizes as (

    select

        cohort_month,

        country,
        device_category,
        channel_group,
        source,
        medium,
        browser,
        os,

        count(distinct user_pseudo_id) as cohort_size

    from first_session

    group by all

)

select

    r.cohort_month,

    r.month_number,

    r.country,
    r.device_category,

    r.channel_group,
    r.source,
    r.medium,

    r.browser,
    r.os,

    r.active_users,

    c.cohort_size,

    round(
        r.active_users
        / nullif(c.cohort_size,0),
        4
    ) as retention_rate

from retention r

left join cohort_sizes c

using (

    cohort_month,

    country,
    device_category,

    channel_group,
    source,
    medium,

    browser,
    os

)