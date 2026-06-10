{{
    config(
        materialized='view'
    )
}}

with sessions as (

    select *
    from {{ ref('stg_ga4__sessions') }}

)

select

    *,

    round(total_engagement_msec / 1000 / 60, 2)
        as engagement_minutes,

    case
        when is_impossible_duration then 'invalid'
        when is_high_event_session then 'suspicious'
        else 'normal'
    end as session_quality,

    case
        when session_duration_min <= 1 then '0-1 min'
        when session_duration_min <= 5 then '1-5 min'
        when session_duration_min <= 15 then '5-15 min'
        when session_duration_min <= 30 then '15-30 min'
        else '30+ min'
    end as duration_bucket,

    case
        when purchases > 0 then 1
        else 0
    end as converted_session

from sessions