# GA4 Ecommerce Analytics Platform

End-to-end analytics engineering project built on Google Analytics 4 public e-commerce data:
BigQuery → dbt → Tableau → GitHub Actions

Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce (Nov 2020 – Jan 2021, ~4.3M events)
Status: Production-style analytics pipeline with testing, data quality monitoring, source freshness validation and documented business marts.

## Project Overview

The goal of the project was to transform raw GA4 event data into a canonical analytics model for:
    * sessions; 
    * orders; 
    * order items; 
    * products; 
    * revenue; 
    * attribution; 
    * funnel; 
    * data quality; 
    * reconciliation. 

---

## Business Objectives

The project addresses common ecommerce analytics use cases:

* Marketing channel performance
* Executive KPI reporting
* Ecommerce funnel analysis
* Customer retention analysis
* Customer lifetime value analysis
* Product performance analysis
* Data quality monitoring
* Revenue reconciliation

---

## Tech Stack

* SQL
* dbt
* Google BigQuery
* Google Analytics 4 Sample Ecommerce Dataset
* Great Expectations
* Tableau Public
* GitHub
* GitHub Actions (CI/CD)

---

### Coverage Metrics

| Metric                    | Value   |
| ------------------------- | ------- |
| Raw events                | ~4.3M   |
| Sessions                  | ~360K   |
| Users                     | ~270K   |
| Purchase events           | 5,692   |
| Unique orders             | 4,451   |
| Revenue reconciled        | 307,640 |
| Data marts                | 6       |

---

## Data Architecture

```text
Raw GA4 Events
      │
      ▼
Staging Layer
      │
      ▼
Intermediate Layer
      │
      ▼
Business Marts
      │
      ▼
Tableau Dashboards
```

### Staging Layer

Purpose: standardize raw GA4 export data and expose business-friendly fields.

Models:

* stg_ga4__events

Key transformations:

* Extracts commonly used values from nested event_params, including session, page, engagement, and event-level attribution parameters.
* Preserves the original event grain: 1 row = 1 GA4 event. 
* Creates a deterministic session_key from user_pseudo_id and ga_session_id.
* Cleans and normalizes traffic source, medium, campaign, and transaction ID values.
* Adds transaction ID status classification (missing, empty, placeholder, valid).
* Calculates item-level revenue and quantity metrics while keeping the event-level grain.
* Reconciles items_revenue against purchase_revenue and flags mismatches.
* Adds boolean event flags for key ecommerce funnel events such as purchase, add_to_cart, begin_checkout, and view_item.
* Generates a technical event fingerprint for data quality and duplicate-event investigation
* Adds data quality and tracking flags for missing session IDs, invalid purchase data, self-referrals, deleted data, and other anomalies.

The resulting model provides a standardized staging layer for downstream session, funnel, attribution, ecommerce, and data quality analysis.

---

### Intermediate Layer

The intermediate layer applies business logic on top of the cleaned GA4 staging data and creates canonical purchase, order-item, and session-level datasets.

Models:

* int_purchase_events_resolved

      Grain: 1 row = 1 GA4 purchase event.
      
      Resolves purchase events into canonical business orders.
      
      Key transformations:
      * Identifies repeated purchase events by transaction_id.
      * Determines the canonical purchase event that creates an order.
      * Generates a deterministic order_key.
      * Preserves repeated and invalid purchases for data quality analysis.
      * Detects cross-user and cross-session transaction collisions.
      * Applies canonical purchase attribution.
      * Reconciles item-level revenue with purchase revenue.
      * Adds purchase and transaction-level diagnostics.

* int_purchase_items

      Grain: 1 row = 1 item in a canonical business order.
      
      Transforms the items array from canonical purchases into item-level records.
      
      Key transformations:
      * Unnests items only from canonical order-creating purchases.
      * Generates order_item_key and product_key.
      * Normalizes product identifiers and product attributes.
      * Builds a three-level product category hierarchy.
      * Exposes item price, quantity, revenue, and promotion data.
      * Inherits canonical purchase attribution, device, and geo attributes.

* int_sessions

      Grain: 1 row = 1 GA4 session.
      
      Aggregates event-level data into a session-level dataset.
      
      Key transformations:
      * Calculates session start, end, and duration.
      * Resolves session-level attribution from event data.
      * Derives session device and geographic attributes.
      * Aggregates event, pageview, engagement, and funnel metrics.
      * Tracks progression through the ecommerce funnel.
      * Adds session quality and tracking diagnostics.
      * Keeps raw purchase event counts for data quality purposes; canonical order metrics are sourced from the order layer downstream.

Layer responsibilities

The intermediate layer separates business logic by grain:

Purchase grain → canonical order resolution.

Item grain → product-level order analysis.

Session grain → sessions, engagement, funnel, and traffic analysis.

This separation prevents duplicated purchases and items from inflating downstream order, revenue, and product metrics.

---

### Source of Truth

Orders & revenue: fct_orders

Order items & product revenue: fct_order_items

Sessions & funnel: fct_sessions

---

### Business Marts

The marts layer contains business-ready metrics designed for reporting and decision making.

* mart_daily_performance
* mart_funnel
* mart_product_performance
* mart_retention
* mart_user_ltv
* mart_data_quality

---

### Data Quality Deep Dive

One of the main goals of the project was ensuring metric consistency across all reporting layers.

The original $84 discrepancy was primarily caused by inconsistent attribution logic between order-level and product-level reporting.

fct_orders uses canonical purchase attribution from the order-creating purchase event, while product-level reporting was previously using session attribution. This caused the same purchase revenue to be assigned to different source/medium/campaign buckets.

The attribution logic was aligned by resolving canonical purchase attribution in int_purchase_events_resolved and propagating it to both fct_orders and fct_order_items.

After the correction, the discrepancy decreased from $84 to $78. This confirms that the attribution inconsistency explained part, but not all, of the difference.

The remaining $78 discrepancy requires a separate reconciliation of revenue aggregation and filtering logic. It should not be resolved by changing attribution rules or artificially adjusting revenue.

#### Final Conclusion

The remaining $78 revenue discrepancy is not caused by missing orders, missing items, or incorrect order resolution.

The investigation showed:
* 5,692 raw purchase events were identified.
* 1,001 purchase events contain a mismatch between GA4 purchase_revenue and the sum of item-level item_revenue, with a total raw discrepancy of $1,099.
* After canonical purchase resolution and duplicate filtering, the remaining difference is $78 across the canonical orders.
* 0 orders are missing from fct_order_items, and $0 revenue is associated with orders without item rows.
* fct_orders correctly uses the canonical GA4 purchase_revenue as the source of truth for order-level revenue.
* fct_order_items correctly uses GA4 item_revenue as the source of truth for item-level revenue.

The remaining $78 is therefore a source-data reconciliation difference between two GA4 revenue measures, not a transformation or modeling defect.

The discrepancy is distributed across multiple orders rather than being caused by a single erroneous record. Attempting to force item-level revenue to equal order-level purchase revenue would introduce artificial adjustments and would make the model less faithful to the source data.

#### Final Modeling Decision

fct_orders.purchase_revenue remains the canonical source for order revenue.

fct_order_items.item_revenue remains the canonical source for item revenue.

Purchase attribution is resolved once in int_purchase_events_resolved and propagated consistently to order and item facts.

The $78 difference should remain visible through reconciliation / data-quality metrics rather than being artificially eliminated.

Conclusion: the revenue model is internally consistent. The remaining $78 represents an observed GA4 source-data discrepancy between order-level and item-level revenue, not a dbt transformation bug.

#### Testing

Automated dbt tests include:
* unique keys
* not null validation
* relationships tests

Audit models are used for verification data integrity and reconciliation between canonical purchase resolution, fct_orders, fct_order_items and fct_sessions. 

Great Expectations: data quality contract for resolved purchase events, covering event identity, transaction status, revenue integrity, resolution logic, attribution fields, and order identification.


### Source Freshness Monitoring

The project includes dbt source freshness monitoring.

freshness:

  warn_after:
    count: 24
    period: hour

  error_after:
    count: 48
    period: hour

Purpose:

monitor source latency
detect stale data
simulate production-grade monitoring

Note:

The public GA4 sample dataset is static, therefore freshness checks are included to demonstrate implementation rather than operational alerting.

### CI/CD

CI/CD is implemented using GitHub Actions.

Every push and pull request automatically runs:
* dbt parse
* dbt build

This ensures that new changes do not break model dependencies or data quality validations.


### Documentation

dbt documentation includes:
* model descriptions
* column descriptions
* lineage graph
* business definitions
* test coverage

<img width="1102" height="666" alt="graph" src="https://github.com/user-attachments/assets/54541a73-270a-4635-91e4-8f2c287bd9b9" />

The lineage graph visualizes how raw GA4 events are transformed into reporting-ready analytical datasets.
