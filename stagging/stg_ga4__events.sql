{{
  config(
    materialized = 'view'
  )
}}

with source as (

    select *
    from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
    where _table_suffix between '20201101' and '20210131'
),



-- ============================================================
-- Extract event_params once
-- FIX:
-- event_params розбираємо в одному CTE.
-- items вже є event-level ARRAY, тому UNNEST(items) тут НЕ потрібен.
-- Це дозволяє зберегти grain:
-- 1 row = 1 GA4 event.
-- ============================================================

event_params_extracted as (

    select
   
        event_date,
        event_timestamp,
        event_name,
        event_previous_timestamp,

        user_pseudo_id,
        user_id,
        event_bundle_sequence_id,
        event_server_timestamp_offset,
        platform,

        traffic_source,

        device,
        geo,

        ecommerce,
        items,

        -- =====================================================
        -- Session
        -- =====================================================

        (
            select p.value.int_value
            from unnest(event_params) as p
            where p.key = 'ga_session_id'
            limit 1
        ) as ga_session_id,

        (
            select p.value.int_value
            from unnest(event_params) as p
            where p.key = 'ga_session_number'
            limit 1
        ) as session_number,

        -- =====================================================
        -- Page
        -- =====================================================

        (
            select p.value.string_value
            from unnest(event_params) as p
            where p.key = 'page_location'
            limit 1
        ) as page_location,

        (
            select p.value.string_value
            from unnest(event_params) as p
            where p.key = 'page_title'
            limit 1
        ) as page_title,

        (
            select p.value.string_value
            from unnest(event_params) as p
            where p.key = 'page_referrer'
            limit 1
        ) as page_referrer,

        -- =====================================================
        -- Engagement
        -- =====================================================

        (
            select p.value.string_value
            from unnest(event_params) as p
            where p.key = 'session_engaged'
            limit 1
        ) as session_engaged_raw,

        (
            select p.value.int_value
            from unnest(event_params) as p
            where p.key = 'engagement_time_msec'
            limit 1
        ) as engagement_time_msec,

        -- =====================================================
        -- Event-level traffic
        -- =====================================================

        (
            select p.value.string_value
            from unnest(event_params) as p
            where p.key = 'source'
            limit 1
        ) as event_source_raw,

        (
            select p.value.string_value
            from unnest(event_params) as p
            where p.key = 'medium'
            limit 1
        ) as event_medium_raw,

        (
            select p.value.string_value
            from unnest(event_params) as p
            where p.key = 'campaign'
            limit 1
        ) as event_campaign_raw

    from source

),

renamed as (

    select
        
        -- =====================================================
        -- Event / Time
        -- =====================================================
        event_date,
        parse_date('%Y%m%d', event_date) as event_date_dt,
        timestamp_micros(event_timestamp) as event_at,
        event_timestamp,

        event_name,
        event_previous_timestamp,
        
        -- =====================================================
        -- User
        -- =====================================================

        user_pseudo_id,
        user_id,

        event_bundle_sequence_id,
        event_server_timestamp_offset,
        
        platform,

        user_pseudo_id is null as has_null_user_pseudo_id,

        -- =====================================================
        -- Session
        -- =====================================================

        ga_session_id,
        session_number,

        case
            when user_pseudo_id is null
                or ga_session_id is null
            then null

            else to_hex(
                md5(
                    concat(
                        user_pseudo_id,
                        '-',
                        cast(ga_session_id as string)
                    )
                )
            )
        end as session_key,

        -- =====================================================
        -- Page
        -- =====================================================

        page_location,
        page_title,
        page_referrer,

        -- =====================================================
        -- Engagement
        -- =====================================================

        session_engaged_raw,
        engagement_time_msec,

        -- =====================================================
        -- Event-level traffic
        -- =====================================================

        nullif(
            nullif(
                nullif(
                    nullif(
                        nullif(
                            trim(event_source_raw),
                            ''
                        ),
                        '(not set)'
                    ),
                    'not set'
                ),
                '<Other>'
            ),
            'undefined'
        ) as event_source,

        nullif(
            nullif(
                nullif(
                    nullif(
                        nullif(
                            trim(event_medium_raw),
                            ''
                        ),
                        '(not set)'
                    ),
                    'not set'
                ),
                '<Other>'
            ),
            'undefined'
        ) as event_medium,


        nullif(
            nullif(
                nullif(
                    nullif(
                        nullif(
                            trim(event_campaign_raw),
                            ''
                        ),
                        '(not set)'
                    ),
                    'not set'
                ),
                '<Other>'
            ),
            'undefined'
        ) as event_campaign,
       

        -- =====================================================
        -- First-touch attribution
        -- =====================================================

        nullif(
            nullif(
                trim(traffic_source.source),
                '(not set)'
            ),
            ''
        ) as first_touch_source,

        nullif(
            nullif(
                trim(traffic_source.medium),
                '(not set)'
            ),
            ''
        ) as first_touch_medium,

        nullif(
            nullif(
                trim(traffic_source.name),
                '(not set)'
            ),
            ''
        ) as first_touch_campaign,

        -- =====================================================
        -- Device
        -- =====================================================

        device.category as device_category,
        device.operating_system as os,
        device.web_info.browser as browser,
        device.language as language,

        -- =====================================================
        -- Geo
        -- =====================================================

        geo.continent as continent,
        geo.country as country,
        geo.region as region,
        nullif(geo.city, '(not set)') as city,

        -- =====================================================
        -- Ecommerce
        -- =====================================================

        ecommerce.transaction_id as transaction_id_raw,

        case
            when ecommerce.transaction_id is null then null

            when trim(ecommerce.transaction_id) = '' then null

            when lower(trim(ecommerce.transaction_id)) in (
                '(not set)',
                'not set',
                '<other>',
                'null',
                'undefined'
            ) then null

            else trim(ecommerce.transaction_id)
        end as transaction_id_normalized,

        case
            when ecommerce.transaction_id is null then 'missing'

            when trim(ecommerce.transaction_id) = '' then 'empty'

            when lower(trim(ecommerce.transaction_id)) in (
                '(not set)',
                'not set',
                '<other>',
                'null',
                'undefined'
            ) then 'placeholder'

            else 'valid'
        end as transaction_id_status,

        ecommerce.purchase_revenue as purchase_revenue,
        ecommerce.purchase_revenue_in_usd as purchase_revenue_usd,
        ecommerce.tax_value as tax_value,
        ecommerce.shipping_value as shipping_value,
        ecommerce.unique_items as unique_items,
        items

    from event_params_extracted

),


final as (

    select

        -- =====================================================
        -- Event / Time
        -- =====================================================

        event_date,
        event_date_dt,
        event_at,
        event_timestamp,
        event_name,
        event_previous_timestamp,

        -- =====================================================
        -- User
        -- =====================================================

        user_pseudo_id,
        user_id,
        event_bundle_sequence_id,
        event_server_timestamp_offset,
        platform,

        has_null_user_pseudo_id,

        -- =====================================================
        -- Session
        -- =====================================================

        ga_session_id,
        session_number,
        session_key,

        -- =====================================================
        -- Page
        -- =====================================================

        page_location,
        page_title,
        page_referrer,

        -- =====================================================
        -- Engagement
        -- =====================================================

        session_engaged_raw,
        engagement_time_msec,

        -- =====================================================
        -- Event-level attribution
        -- =====================================================

        event_source,
        event_medium,
        event_campaign,

        -- =====================================================
        -- First-touch attribution
        -- =====================================================

        first_touch_source,
        first_touch_medium,
        first_touch_campaign,

        -- =====================================================
        -- Device
        -- =====================================================

        device_category,
        os,
        browser,
        language,

        -- =====================================================
        -- Geo
        -- =====================================================

        continent,
        country,
        region,
        city,

        -- =====================================================
        -- Ecommerce
        -- =====================================================

        transaction_id_raw,
        transaction_id_normalized,
        transaction_id_status,

        purchase_revenue,
        purchase_revenue_usd,
        tax_value,
        shipping_value,
        unique_items,

        items,

        (
            select
                sum(coalesce(item.item_revenue, 0))
            from unnest(items) as item
        ) as items_revenue,

        (
            select
                sum(coalesce(item.quantity, 0))
            from unnest(items) as item
        ) as items_quantity,

        coalesce(
            (
                select sum(coalesce(item.item_revenue, 0))
                from unnest(items) as item
            ),
            0
        )
        -
        coalesce(purchase_revenue, 0)
        as item_to_purchase_revenue_diff
        ,

        coalesce(
            event_name = 'purchase'
            and abs(
                coalesce(
                    (
                        select sum(coalesce(item.item_revenue, 0))
                        from unnest(items) as item
                    ),
                    0
                )
                -
                coalesce(purchase_revenue, 0)
            ) > 0,
            false
        ) as flag_item_purchase_revenue_mismatch,

        -- =====================================================
        -- Event identity
        -- =====================================================
        --
        -- Technical event fingerprint (for technical DQ, investigation potential duplicate events).
    
        to_hex(
            md5(
                concat(
                    coalesce(
                        user_pseudo_id,
                        '__null_user__'
                    ),
                    '-',
                    cast(
                        event_timestamp as string
                    ),
                    '-',
                    event_name,
                    '-',
                    coalesce(
                        cast(
                            ga_session_id as string
                        ),
                        '__null_session__'
                    )
                )
            )
        ) as technical_event_fingerprint,

        -- =====================================================
        -- Event flags
        -- =====================================================

        coalesce(
            event_name = 'purchase',
            false
        ) as is_purchase,

        coalesce(
            event_name = 'add_to_cart',
            false
        ) as is_add_to_cart,

        coalesce(
            event_name = 'begin_checkout',
            false
        ) as is_begin_checkout,

        coalesce(
            event_name = 'add_payment_info',
            false
        ) as is_add_payment_info,

        coalesce(
            event_name = 'add_shipping_info',
            false
        ) as is_add_shipping_info,

        coalesce(
            event_name = 'view_item',
            false
        ) as is_view_item,

        coalesce(
            event_name = 'page_view',
            false
        ) as is_page_view,

        coalesce(
            event_name = 'session_start',
            false
        ) as is_session_start,

        coalesce(
            event_name = 'first_visit',
            false
        ) as is_first_visit,

        coalesce(
            session_engaged_raw = '1',
            false
        ) as is_engaged_session_event,

        -- =====================================================
        -- Data quality
        -- =====================================================
  
        coalesce(
            event_name = 'purchase'
            and transaction_id_normalized is null,
            false
        ) as flag_missing_transaction_id,

        coalesce(
            event_name = 'purchase'
            and purchase_revenue is null,
            false
        ) as flag_null_purchase_revenue,

        coalesce(
            event_name = 'purchase'
            and purchase_revenue < 0,
            false
        ) as flag_negative_purchase_revenue,

        coalesce(
            ga_session_id is null,
            false
        ) as flag_missing_session_id,

        -- =====================================================
        -- Attribution / tracking DQ
        -- =====================================================

        coalesce(
            first_touch_source
                = 'shop.googlemerchandisestore.com'
            and first_touch_medium
                = 'referral',
            false
        ) as flag_self_referral,

        coalesce(
            event_source
                = 'shop.googlemerchandisestore.com'
            and event_medium
                = 'referral',
            false
        ) as flag_event_self_referral,

        coalesce(
            first_touch_source = '(data deleted)',
            false
        ) as flag_data_deleted

    from renamed

)


select
        event_date,
        event_date_dt,
        event_at,
        event_timestamp,
        event_name,
        event_previous_timestamp,
        user_pseudo_id,
        user_id,
        event_bundle_sequence_id,
        event_server_timestamp_offset,
        platform,
        has_null_user_pseudo_id,
        ga_session_id,
        session_number,
        session_key,
        page_location,
        page_title,
        page_referrer,
        session_engaged_raw,
        engagement_time_msec,
        event_source,
        event_medium,
        event_campaign,
        first_touch_source,
        first_touch_medium,
        first_touch_campaign,
        device_category,
        os,
        browser,
        language,
        continent,
        country,
        region,
        city,
        transaction_id_raw,
        transaction_id_normalized,
        transaction_id_status,
        purchase_revenue,
        purchase_revenue_usd,
        tax_value,
        shipping_value,
        unique_items,
        items,
        items_revenue,
        items_quantity,
        item_to_purchase_revenue_diff,
        flag_item_purchase_revenue_mismatch,
        technical_event_fingerprint,
        is_purchase,
        is_add_to_cart,
        is_begin_checkout,
        is_add_payment_info,
        is_add_shipping_info,
        is_view_item,
        is_page_view,
        is_session_start,
        is_first_visit,
        is_engaged_session_event,
        flag_missing_transaction_id,
        flag_null_purchase_revenue,
        flag_negative_purchase_revenue,
        flag_missing_session_id,
        flag_self_referral,
        flag_event_self_referral,
        flag_data_deleted
  from final
