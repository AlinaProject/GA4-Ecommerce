{{ config(
    materialized = 'table',
    cluster_by = [
        'self_referral_type'
    ],
    description = 'Audit of GA4 attribution and self-referral anomalies.'
) }}

select

    event_date_dt as audit_date,

    technical_event_fingerprint,

    user_pseudo_id,

    session_key,

    first_touch_source,
    first_touch_medium,
    first_touch_campaign,

    event_source,
    event_medium,
    event_campaign,

    case

        when flag_self_referral
         and flag_event_self_referral
            then 'BOTH'

        when flag_self_referral
            then 'FIRST_TOUCH'

        when flag_event_self_referral
            then 'EVENT_LEVEL'

        else 'UNKNOWN'

    end as self_referral_type

from {{ ref('stg_ga4__events') }}

where flag_self_referral
   or flag_event_self_referral
