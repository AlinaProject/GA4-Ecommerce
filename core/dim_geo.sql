{{ config(
    materialized = 'table',
    cluster_by = ['country', 'region']
) }}

with geo as (

    select

        continent,
        country,
        region,
        city

    from {{ ref('int_sessions') }}

),

final as (

    select distinct

        {{ generate_key([
            'continent',
            'country',
            'region',
            'city'
        ]) }} as geo_key,

        continent,
        country,
        region,
        city

    from geo

)

select geo_key,
    continent,
    country,
    region,
    city
from final
