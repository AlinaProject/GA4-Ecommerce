{{ config(
    materialized='table'
) }}

with null_checks as (

    select

        'missing_transaction_id' as check_name,

        countif(flag_missing_txn_id) as issue_count,

        round(
            100 * countif(flag_missing_txn_id)
            / nullif(countif(is_purchase),0),
            2
        ) as issue_pct

    from {{ ref('stg_ga4__events') }}

),

duplicate_checks as (

    select

        'duplicate_transaction_id_before_clustering' as check_name,

        count(*) as issue_count,

        round(
            100 * count(*) /
            nullif(
                (
                    select count(*)
                    from {{ ref('stg_ga4__events') }}
                    where is_purchase
                ),
                0
            ),
            2
        ) as issue_pct

    from (

        select
            transaction_id

        from {{ ref('stg_ga4__events') }}

        where is_purchase
          and transaction_id is not null
          and transaction_id != '(not set)'

        group by 1

        having count(*) > 1

    )

),

revenue_checks as (

    select

        'negative_revenue' as check_name,

        count(*) as issue_count,

        round(100 * count(*) / nullif((select count(*) from {{ ref('stg_ga4__events') }} where is_purchase), 0), 2) as issue_pct

    from {{ ref('stg_ga4__events') }}

    where purchase_revenue < 0

),

session_checks as (

    select

        'high_event_sessions' as check_name,

        count(*) as issue_count,

        round(100 * count(*) / (select count(*) from {{ ref('int_sessions') }}), 2) as issue_pct

    from {{ ref('int_sessions') }}

    where is_high_event_session

),

duration_checks as (

    select

        'impossible_duration' as check_name,

        count(*) as issue_count,

        round(100 * count(*) / (select count(*) from {{ ref('int_sessions') }}), 2) as issue_pct

    from {{ ref('int_sessions') }}

    where is_impossible_duration

),

freshness_checks as (

    select

        'data_freshness' as check_name,

        timestamp_diff(
            current_timestamp(),
            max(event_at),
            hour
        ) as issue_count,

        null as issue_pct

    from {{ ref('stg_ga4__events') }}

),

all_checks as (

    select * from null_checks

    union all

    select * from duplicate_checks

    union all

    select * from revenue_checks

    union all

    select * from session_checks

    union all

    select * from duration_checks

    union all

    select * from freshness_checks

)

select

    *,

    case

        when check_name='data_freshness'
             and issue_count > 49
        then 'ERROR'

        when issue_count > 0
             and check_name in (
                 'missing_transaction_id',
                 'negative_revenue',
                 'impossible_duration'
             )
        then 'FAILED'

        when issue_count > 0
        then 'WARNING'

        else 'PASSED'

    end as check_status,

    case

        when check_name='data_freshness'
             and issue_count > 49
        then 4

        when issue_count > 0
             and check_name in (
                 'missing_transaction_id',
                 'negative_revenue',
                 'impossible_duration'
             )
        then 3

        when issue_count > 0
        then 2

        else 1

    end as status_sort,

    current_timestamp() as audit_ts

from all_checks