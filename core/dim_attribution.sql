{{ config(
    materialized = 'table',
    description = 'Attribution dimension. One row = one unique source / medium / campaign combination.',
    cluster_by = ['source', 'medium']
) }}

with attribution as (

    select
        event_source as source,
        event_medium as medium,
        event_campaign as campaign

    from {{ ref('int_purchase_events_resolved') }}

    where is_order_creating_purchase = true

    union distinct

    select
        first_touch_source as source,
        first_touch_medium as medium,
        first_touch_campaign as campaign

    from {{ ref('stg_ga4__events') }}

    where
        first_touch_source is not null
        or first_touch_medium is not null
        or first_touch_campaign is not null

    union distinct

    select
        session_attribution.source as source,
        session_attribution.medium as medium,
        session_attribution.campaign as campaign

    from {{ ref('int_sessions') }}

    where session_attribution is not null

),

final as (

    select

        {{ generate_key([
            'source',
            'medium',
            'campaign'
        ]) }} as attribution_key,

        source,
        medium,
        campaign,

        case
            when source is null
                and medium is null
                then 'Direct'

            when lower(medium) = 'organic'
                then 'Organic Search'

            when lower(medium) in ('cpc', 'ppc')
                then 'Paid Search'

            when lower(medium) = 'referral'
                then 'Referral'

            when lower(medium) = 'email'
                then 'Email'

            when lower(medium) in (
                'social',
                'social-network',
                'social_media'
            )
                then 'Social'

            when lower(medium) = 'display'
                then 'Display'

            when lower(medium) = 'affiliate'
                then 'Affiliate'

            else 'Other'

        end as channel_group

    from attribution

)

select
    attribution_key,
    source,
    medium,
    campaign,
    channel_group

from final
