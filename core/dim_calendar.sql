{{ config(
    materialized = 'table',
    description = 'Calendar dimension.'
) }}

with dates as (

    select date_day

    from unnest(
        generate_date_array(
            date('2020-01-01'),
            date('2030-12-31'),
            interval 1 day
        )
    ) as date_day

),

final as (

    select

        date_day,
        date_day as date_key,

        extract(year from date_day) as year,

        extract(quarter from date_day) as quarter,

        extract(month from date_day) as month,

        extract(day from date_day) as day,

        extract(dayofweek from date_day) as day_of_week,

        extract(isoweek from date_day) as iso_week,

        extract(isoyear from date_day) as iso_year,

        format_date('%A', date_day) as day_name,

        format_date('%B', date_day) as month_name,

        format_date('%Y-%m', date_day) as year_month,

        date_trunc(date_day, week(monday)) as week_start,

        date_trunc(date_day, month) as month_start,

        date_trunc(date_day, quarter) as quarter_start,

        date_trunc(date_day, year) as year_start,

        extract(dayofweek from date_day) in (1, 7)
            as is_weekend

    from dates

)

select f.date_day,
    f.date_key,
    f.year,
    f.quarter,
    f.month,
    f.day,
    f.day_of_week,
    f.iso_week,
    f.iso_year,
    f.day_name,
    f.month_name,
    f.year_month,
    f.week_start,
    f.month_start,
    f.quarter_start,
    f.year_start,
    f.is_weekend
from final f
