# GA4 Ecommerce Analytics Platform

End-to-end analytics engineering project built on Google Analytics 4 public e-commerce data:
BigQuery → dbt → Tableau.


Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce (Nov 2020 – Jan 2021, ~4.3M events, read directly, zero-copy)
Status: staging + intermediate + marts layers complete, tested, and reconciled to the cent.

What this project demonstrates


* Parsing raw, deeply nested GA4 BigQuery export data (UNNEST'd event params and items arrays)
* A clean staging → intermediate → marts dbt architecture, with marts consolidated to avoid
duplicate business logic across dashboards
* A real, non-trivial data-quality investigation: finding, diagnosing, and fixing a revenue
discrepancy caused by a non-unique natural key — see Data Quality Deep Dive
* An automated test suite built around cross-model consistency, not just column-level checks
* Business-ready marts feeding Tableau dashboards (Executive Overview, Marketing Performance, Funnel)

---

## Business Objectives

The project addresses several common ecommerce analytics challenges:

* Measure acquisition performance by marketing channel
* Track user behavior through the ecommerce funnel
* Analyze customer retention and lifetime value
* Monitor executive KPIs
* Detect and document data quality issues
* Create trusted reporting datasets for BI consumption

---

## Tech Stack

* SQL
* dbt
* Google BigQuery
* Google Analytics 4 Sample Ecommerce Dataset
* Tableau Public
* GitHub

---

## Data Architecture

Raw GA4 Events
↓
Staging Layer
↓
Intermediate Layer
↓
Business Marts
↓
BI Dashboard

### Staging Layer

Raw GA4 events are standardized and enriched.

Models:

* stg_ga4__events

Key transformations:

* Event normalization
* Channel grouping
* Data quality flags
* Transaction validation

---

### Intermediate Layer

Business logic is separated from reporting models.

Models:

* int_sessions
* int_funnel_steps
* int_user_metrics

Purpose:

* Funnel preparation
* Session reconstruction
* User-level metric calculation

---

### Business Marts

The marts layer contains business-ready metrics designed for reporting and decision making.

#### mart_executive_kpi

Executive-level daily performance metrics:

* Revenue
* Sessions
* Users
* Purchases
* Conversion Rate
* Average Order Value

#### mart_product_performance

Product performance metrics based on deduplicated transactions:

* product revenue
* quantity sold
* average item price
* transaction metrics

#### mart_funnel

Normalized ecommerce funnel:

* View Item
* Add To Cart
* Begin Checkout
* Purchase

#### mart_retention

Customer retention metrics:

* Cohort analysis
* Day 1 retention
* Day 7 retention
* Day 30 retention

#### mart_user_ltv

User-level lifetime value dataset:

* Revenue per user
* Session frequency
* Lifetime duration
* Purchase behavior

#### mart_data_quality

Centralized data quality monitoring:

* Missing transaction IDs
* Duplicate transaction IDs
* Revenue validation
* Session anomalies
* Data freshness checks

---

## Documentation

The project includes dbt documentation generated from model and column metadata.

Documentation covers:

model descriptions
key business metrics
column definitions
data quality tests
lineage graph showing dependencies between models

Example documentation includes:

model descriptions
column definitions
lineage graph
data relationships

<img width="1285" height="804" alt="image" src="https://github.com/user-attachments/assets/b108a593-3d08-4646-8eae-918f3069bdd6" />


The lineage graph provides a visual representation of how raw GA4 events are transformed into analytical datasets and business-ready marts.

---

## Data Quality Findings

Several issues were identified during exploratory analysis and addressed within the pipeline.

### Duplicate Purchase Events

Purchase events contained duplicated transaction IDs.

Findings:

* 4,786 purchase events
* 4,451 unique transactions
* 335 duplicated purchase events

Solution:

Purchase events are deduplicated using:

ROW_NUMBER() OVER (
PARTITION BY transaction_id
ORDER BY event_timestamp
)

Only the first occurrence of each transaction is retained.

---

### Missing Transaction IDs

Some purchase events were missing transaction identifiers.

Findings:

* 906 purchase events without valid transaction IDs

Impact:

These events are excluded from revenue calculations to avoid metric inflation.

---

### Funnel Anomalies

Sessions were detected where users reached checkout without a preceding add_to_cart event.

Impact:

Traditional funnel calculations produced conversion rates above 100%.

Solution:

A normalized sequential funnel was implemented to ensure valid step progression.

---

## Testing

The project includes both schema tests and custom SQL tests.

Examples:

* Not Null Tests
* Unique Session ID Tests
* Funnel Validation Tests
* Revenue Validation Tests
* Retention Validation Tests
* LTV Validation Tests

All business marts are validated through automated dbt testing.

---

## Key Skills Demonstrated

* Analytics Engineering
* SQL Development
* Data Modeling
* dbt
* BigQuery
* Data Quality Monitoring
* Funnel Analytics
* Cohort Analysis
* Customer Lifetime Value Analysis

---

## Repository Structure

models/
├── staging/
├── intermediate/
└── marts/

tests/


README.md

eda_findings.md
