{{
  config(
    materialized = 'view',
    description  = 'Staging GA4 подій. Публічний датасет bigquery-public-data.'
  )
}}

with source as (
    -- Публічний датасет використовується напряму через wildcard
    -- Не потрібно копіювати дані
    select *
    from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
    where _table_suffix between '20201101' and '20210131'
),

renamed as (
    select

        -- ── Час ──────────────────────────────────────────
        event_date,
        parse_date('%Y%m%d', event_date)            as event_date_dt,
        timestamp_micros(event_timestamp)            as event_at,
        event_timestamp,

        -- ── Юзер ─────────────────────────────────────────
        user_pseudo_id,
        user_id,
        platform,

        -- ── Event ────────────────────────────────────────
        event_name,

        -- ── Session (з event_params через scalar subquery) ─
        (
            select value.int_value
            from unnest(event_params)
            where key = 'ga_session_id'
        )                                            as ga_session_id,

        (
            select value.int_value
            from unnest(event_params)
            where key = 'ga_session_number'
        )                                            as session_number,

        -- ── Page ─────────────────────────────────────────
        (
            select value.string_value
            from unnest(event_params)
            where key = 'page_location'
        )                                            as page_location,

        (
            select value.string_value
            from unnest(event_params)
            where key = 'page_title'
        )                                            as page_title,

        (
            select value.string_value
            from unnest(event_params)
            where key = 'page_referrer'
        )                                            as page_referrer,

        -- ── Engagement ───────────────────────────────────
        (
            select value.string_value
            from unnest(event_params)
            where key = 'session_engaged'
        )                                            as session_engaged_raw,

        (
            select value.int_value
            from unnest(event_params)
            where key = 'engagement_time_msec'
        )                                            as engagement_time_msec,

        -- ── Traffic (session-level, точніше ніж STRUCT) ──
        -- DQ: (none) і <Other> → NULL
        nullif(
            (select value.string_value from unnest(event_params)
             where key = 'source'), '<Other>'
        )                                            as session_source,

        nullif(
            nullif(
                (select value.string_value from unnest(event_params)
                 where key = 'medium'), '<Other>'
            ), '(none)'
        )                                            as session_medium,

        (
            select value.string_value
            from unnest(event_params)
            where key = 'campaign'
        )                                            as session_campaign,

        -- ── Traffic STRUCT (first-touch attribution) ─────
        nullif(traffic_source.source, '<Other>')     as traffic_source,
        nullif(traffic_source.medium, '<Other>')     as traffic_medium,
        nullif(traffic_source.name, '<Other>')       as traffic_campaign,

        -- ── Device ───────────────────────────────────────
        device.category                              as device_category,
        device.operating_system                      as os,
        device.web_info.browser                      as browser,
        device.language                              as language,

        -- ── Geo ──────────────────────────────────────────
        geo.continent                                as continent,
        geo.country                                  as country,
        geo.region                                   as region,
        nullif(geo.city, '(not set)')                as city,

        -- ── Ecommerce (тільки для purchase) ──────────────
        ecommerce.transaction_id                     as transaction_id,
        ecommerce.purchase_revenue                   as purchase_revenue,
        ecommerce.tax_value                          as tax_value,
        ecommerce.shipping_value                     as shipping_value,
        ecommerce.unique_items                       as unique_items,
        items                    as items
       

    from source
),

final as (
    select
        *,

        -- ── Event type flags ─────────────────────────────
        event_name = 'purchase'             as is_purchase,
        event_name = 'add_to_cart'          as is_add_to_cart,
        event_name = 'begin_checkout'       as is_begin_checkout,
        event_name = 'add_payment_info'     as is_add_payment_info,
        event_name = 'add_shipping_info'    as is_add_shipping_info,
        event_name = 'view_item'            as is_view_item,
        event_name = 'page_view'            as is_page_view,
        event_name = 'session_start'        as is_session_start,
        event_name = 'first_visit'          as is_first_visit,

        -- ── Engagement flag ──────────────────────────────
        session_engaged_raw = '1'           as is_session_engaged,

        -- ── Channel grouping ─────────────────────────────
        case
            when session_medium = 'organic'                       then 'Organic Search'
            when session_medium in ('cpc', 'ppc', 'paid')         then 'Paid Search'
            when session_medium in ('email', 'e-mail', 'mail')    then 'Email'
            when session_medium in ('social', 'social-network')   then 'Organic Social'
            when session_medium = 'referral'                      then 'Referral'
            when session_medium = 'affiliate'                     then 'Affiliates'
            when session_source = '(direct)' or session_source is null
                                                                  then 'Direct'
            else 'Other'
        end                                 as channel_group,

        -- ── DQ flags (знайдено в аналізі) ────────────────

        -- Internal cross-domain (shop.googlemerchandisestore.com)
        traffic_source = 'shop.googlemerchandisestore.com'
          and traffic_medium = 'referral'   as is_internal_referral,

        -- GDPR / Consent Mode deleted data
        traffic_source = '(data deleted)'   as is_gdpr_deleted,

        -- Purchase без transaction_id (23 події, 0.4%)
        (
            event_name = 'purchase'
            and (transaction_id is null or transaction_id = '(not set)')
        )                                   as flag_missing_txn_id,

        (
            event_name = 'purchase'
            and purchase_revenue is null
        )                                   as flag_null_revenue

    from renamed
)

select * from final