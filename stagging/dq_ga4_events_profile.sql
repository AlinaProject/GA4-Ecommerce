{{ config(
materialized = 'table',
description = 'Column-level NULL profiling for stg_ga4__events.'
) }}

with source as (

select *
from {{ ref('stg_ga4__events') }}


),

stats as (

select
    count(*) as total_rows,

    countif(event_date is null) as event_date,
    countif(event_date_dt is null) as event_date_dt,
    countif(event_at is null) as event_at,
    countif(event_timestamp is null) as event_timestamp,
    countif(event_name is null) as event_name,
    countif(event_previous_timestamp is null) as event_previous_timestamp,

    countif(user_pseudo_id is null) as user_pseudo_id,
    countif(user_id is null) as user_id,
    countif(event_bundle_sequence_id is null) as event_bundle_sequence_id,
    countif(event_server_timestamp_offset is null) as event_server_timestamp_offset,

    countif(platform is null) as platform,
    countif(has_null_user_pseudo_id is null) as has_null_user_pseudo_id,

    countif(ga_session_id is null) as ga_session_id,
    countif(session_number is null) as session_number,
    countif(session_key is null) as session_key,

    countif(page_location is null) as page_location,
    countif(page_title is null) as page_title,
    countif(page_referrer is null) as page_referrer,

    countif(session_engaged_raw is null) as session_engaged_raw,
    countif(engagement_time_msec is null) as engagement_time_msec,

    countif(event_source is null) as event_source,
    countif(event_medium is null) as event_medium,
    countif(event_campaign is null) as event_campaign,

    countif(first_touch_source is null) as first_touch_source,
    countif(first_touch_medium is null) as first_touch_medium,
    countif(first_touch_campaign is null) as first_touch_campaign,

    countif(device_category is null) as device_category,
    countif(os is null) as os,
    countif(browser is null) as browser,
    countif(language is null) as language,

    countif(continent is null) as continent,
    countif(country is null) as country,
    countif(region is null) as region,
    countif(city is null) as city,

    countif(transaction_id_raw is null) as transaction_id_raw,
    countif(transaction_id_normalized is null) as transaction_id_normalized,
    countif(transaction_id_status is null) as transaction_id_status,

    countif(purchase_revenue is null) as purchase_revenue,
    countif(purchase_revenue_usd is null) as purchase_revenue_usd,
    countif(tax_value is null) as tax_value,
    countif(shipping_value is null) as shipping_value,
    countif(unique_items is null) as unique_items,

    countif(technical_event_fingerprint is null) as technical_event_fingerprint,

    countif(is_purchase is null) as is_purchase,
    countif(is_add_to_cart is null) as is_add_to_cart,
    countif(is_begin_checkout is null) as is_begin_checkout,
    countif(is_add_payment_info is null) as is_add_payment_info,
    countif(is_add_shipping_info is null) as is_add_shipping_info,
    countif(is_view_item is null) as is_view_item,
    countif(is_page_view is null) as is_page_view,
    countif(is_session_start is null) as is_session_start,
    countif(is_first_visit is null) as is_first_visit,
    countif(is_engaged_session_event is null) as is_engaged_session_event,

    countif(flag_missing_transaction_id is null) as flag_missing_transaction_id,
    countif(flag_null_purchase_revenue is null) as flag_null_purchase_revenue,
    countif(flag_negative_purchase_revenue is null) as flag_negative_purchase_revenue,
    countif(flag_missing_session_id is null) as flag_missing_session_id,
    countif(flag_self_referral is null) as flag_self_referral,
    countif(flag_event_self_referral is null) as flag_event_self_referral,
    countif(flag_data_deleted is null) as flag_data_deleted

from source


),

profile as (

select
    total_rows,
    column_name,
    null_count

from stats

unpivot (
    null_count for column_name in (

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

    )
)


)

select
column_name,
total_rows,
null_count,

round(
    safe_divide(null_count * 100, total_rows),
    2
) as null_pct


from profile

order by
null_pct desc,
column_name