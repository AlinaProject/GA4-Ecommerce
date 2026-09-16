{{ config(
    materialized = 'table',
    cluster_by = ['device_category', 'os']
) }}

with devices as (

    select
        device_category,
        os,
        browser

    from {{ ref('int_sessions') }}
    where
        device_category is not null
        or os is not null
        or browser is not null

),

final as (

    select distinct

        {{ generate_key([
            'device_category',
            'os',
            'browser'
        ]) }} as device_key,

        d.device_category,
        d.os,
        d.browser

    from devices d

)

select device_key, 
    device_category,
    os,
    browser
from final
