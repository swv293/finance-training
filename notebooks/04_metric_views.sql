-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03 · Metric Views — Building the Genie Semantic Layer
-- MAGIC **Finance Team · Databricks Workshop**
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## Learning Objectives
-- MAGIC By the end of this notebook you will be able to:
-- MAGIC - Explain what a metric view is and why it improves Genie answers
-- MAGIC - Create a metric view using the `WITH METRICS LANGUAGE YAML` syntax
-- MAGIC - Define dimensions and measures with business-meaningful descriptions
-- MAGIC - Query a metric view using the `MEASURE()` aggregate function
-- MAGIC - Add the metric view to a Genie space for natural language querying
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## What Is a Metric View?
-- MAGIC
-- MAGIC A **metric view** is a semantic layer — a structured description of your data
-- MAGIC that sits between raw tables and the end user (or Genie).
-- MAGIC
-- MAGIC **Without a metric view**, Genie has to guess:
-- MAGIC - Which table does "denial rate" come from?
-- MAGIC - What is the formula for "collection rate"?
-- MAGIC - How do I join claims to AR aging?
-- MAGIC
-- MAGIC **With a metric view**, you've told Genie:
-- MAGIC - These are the tables to use and how to join them
-- MAGIC - These are the dimensions (how to slice the data)
-- MAGIC - These are the measures (what the numbers mean and how to calculate them)
-- MAGIC
-- MAGIC The result: **consistent, auditable answers** every time someone asks a finance question.
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## Metric View YAML Structure
-- MAGIC
-- MAGIC ```yaml
-- MAGIC version: 1.1
-- MAGIC comment: >
-- MAGIC   Human-readable description of what this view covers.
-- MAGIC   Genie uses this comment to understand the domain context.
-- MAGIC
-- MAGIC source: catalog.schema.fact_table   # primary (fact) table
-- MAGIC
-- MAGIC joins:                               # dimension or related tables
-- MAGIC   - name: alias
-- MAGIC     source: catalog.schema.dim_table
-- MAGIC     "on": source.fk = alias.pk
-- MAGIC
-- MAGIC dimensions:                          # columns to slice/filter by
-- MAGIC   - name: column_name
-- MAGIC     expr: source.column              # SQL expression
-- MAGIC     comment: "Business description"
-- MAGIC
-- MAGIC measures:                            # aggregated numbers
-- MAGIC   - name: metric_name
-- MAGIC     expr: |                          # SQL aggregation
-- MAGIC       SUM(source.amount)
-- MAGIC     comment: "What this number means"
-- MAGIC ```

-- COMMAND ----------

-- 🔧 Set your context
USE CATALOG main;
USE SCHEMA finance_training_firstname;   -- ← change this

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 1 — Verify the Underlying Joins
-- MAGIC
-- MAGIC Before creating the metric view, confirm the joins work correctly.
-- MAGIC This is the same data the metric view will use internally.

-- COMMAND ----------

-- 1a. Confirm gold_ar_aging ↔ silver_claims join
--     Every AR record should have a corresponding claim.
SELECT
  a.ar_id,
  a.aging_bucket,
  a.balance_amount,
  a.recovery_score,
  c.claim_status,
  c.lob,
  c.billed_amount,
  c.paid_amount
FROM gold_ar_aging a
JOIN silver_claims c ON a.claim_id = c.claim_id
LIMIT 10;

-- COMMAND ----------

-- 1b. Confirm the full three-way join: AR → claims → denials
--     Note: LEFT JOIN for denials — not every AR record has a denial record
SELECT
  a.ar_id,
  a.aging_bucket,
  c.lob,
  c.claim_status,
  d.denial_category,
  d.carc_code,
  d.is_appealed
FROM gold_ar_aging a
JOIN silver_claims   c ON a.claim_id = c.claim_id
LEFT JOIN silver_denials d ON a.claim_id = d.claim_id
LIMIT 10;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 2 — Create the Metric View
-- MAGIC
-- MAGIC Run this cell to create `mv_rcm_finance`.
-- MAGIC It will take ~10–15 seconds to compile the YAML and register the view.
-- MAGIC
-- MAGIC **Walk through each YAML section as you read it:**
-- MAGIC 1. `source` → the fact table (gold_ar_aging is the center of the model)
-- MAGIC 2. `joins` → bring in claims, denials, and provider data
-- MAGIC 3. `dimensions` → the axes you'll GROUP BY in Genie questions
-- MAGIC 4. `measures` → the numbers and exactly how to calculate them

-- COMMAND ----------

CREATE OR REPLACE VIEW mv_rcm_finance
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: >
  RCM Finance metric view for the training workshop.

  COVERAGE: Claims, denials, AR aging, and cash collections across
  Medicare Advantage (MA), Medicaid (MCD), and Commercial (COM) lines of business.

  PRIMARY SOURCE: gold_ar_aging (one row per open AR balance)
  JOINED TO: silver_claims (claim-level details), silver_denials (denial records),
             bronze_providers (specialty, tier, network status)

  KEY MEASURES:
    - denial_rate: denied claims / total claims * 100. Target < 6%.
    - collection_rate: paid / billed * 100. Target > 90%.
    - total_ar_balance: sum of outstanding balances. Aged AR > 120 days is hardest to collect.
    - avg_days_in_ar: average days outstanding. Target < 40 days.
    - appeal_rate / appeal_approval_rate: how aggressively claims are appealed and won.

  GENIE QUERY TIPS:
    - "AR" or "accounts receivable" = total_ar_balance measure
    - "denial rate" = denial_rate measure (already calculated as %)
    - "collection rate" = collection_rate measure
    - For trends: ask "by month" or "over time" → Genie groups by service_month
    - For LOB comparison: "compare MA to Medicaid" → Genie filters/groups by lob
    - "high-risk AR" = aging_bucket = '120+' AND recovery_score < 0.20

source: main.finance_training_firstname.gold_ar_aging

joins:
  - name: silver_claims
    source: main.finance_training_firstname.silver_claims
    "on": source.claim_id = silver_claims.claim_id

  - name: silver_denials
    source: main.finance_training_firstname.silver_denials
    "on": source.claim_id = silver_denials.claim_id

  - name: bronze_providers
    source: main.finance_training_firstname.bronze_providers
    "on": silver_claims.provider_id = bronze_providers.provider_id

dimensions:
  - name: lob
    expr: silver_claims.lob
    comment: >
      Line of business: MA (Medicare Advantage), MCD (Managed Medicaid), COM (Commercial).
      Use to compare performance across plan types.

  - name: state
    expr: source.state
    comment: >
      US state where services were rendered.
      Primary states: FL, TX, KY, OH, GA, LA, TN, IN, SC, PR.

  - name: aging_bucket
    expr: source.aging_bucket
    comment: >
      AR aging bucket showing how long a balance has been outstanding:
      0-30, 31-60, 61-90, 91-120, 120+.
      Older buckets have progressively lower recovery probability.

  - name: denial_category
    expr: silver_denials.denial_category
    comment: >
      Root cause category of the denial:
        prior_auth     - Missing or invalid authorization (CARC CO-197)
        medical_necessity - Service not deemed necessary (CARC CO-50)
        coding_error   - Billing/coding error (CARC CO-16) — fastest to fix
        timely_filing  - Submitted past deadline (CARC CO-29)
        duplicate      - Already adjudicated (CARC OA-18) — usually write-off

  - name: carc_code
    expr: silver_denials.carc_code
    comment: "ANSI Claim Adjustment Reason Code — standard denial code across payers"

  - name: claim_type
    expr: silver_claims.claim_type
    comment: "Professional, Inpatient, Outpatient, DME, or Pharmacy"

  - name: provider_tier
    expr: bronze_providers.provider_tier
    comment: >
      Provider network tier: tier_1 (preferred), tier_2 (standard), tier_3 (non-preferred).
      Tier_1 providers typically have lower denial rates due to stronger contract alignment.

  - name: specialty
    expr: bronze_providers.specialty
    comment: >
      Provider clinical specialty:
      PCP, Cardiology, Orthopedics, Oncology, Behavioral Health,
      Emergency, SNF, Home Health, Radiology, Physical Therapy

  - name: service_month
    expr: DATE_TRUNC('month', silver_claims.service_date_dt)
    comment: >
      Month of service (first day of month). Use for trend analysis.
      Example: '2024-01-01' = January 2024.

  - name: service_year
    expr: YEAR(silver_claims.service_date_dt)
    comment: "Calendar year of service — use for year-over-year comparisons"

  - name: is_network
    expr: bronze_providers.is_network
    comment: "TRUE = in-network provider; FALSE = out-of-network (higher cost, lower payment rates)"

  - name: denial_related
    expr: source.denial_related
    comment: "TRUE if this AR record is associated with a denied claim"

measures:
  - name: total_ar_balance
    expr: SUM(source.balance_amount)
    comment: >
      Total outstanding AR balance in dollars.
      Represents money billed but not yet collected.
      Compare by aging_bucket to see where the most money is at risk.

  - name: record_count
    expr: COUNT(source.ar_id)
    comment: "Number of open AR records (one per outstanding claim balance)"

  - name: denial_rate
    expr: >
      ROUND(
        COUNT(CASE WHEN silver_claims.claim_status = 'DENIED' THEN 1 END) * 100.0
        / NULLIF(COUNT(silver_claims.claim_id), 0),
        2
      )
    comment: >
      Denial rate as a percentage of total claims.
      Formula: denied claims / total claims * 100.
      Industry benchmark: below 6%. Above 10% indicates a systemic process issue.

  - name: collection_rate
    expr: >
      ROUND(
        SUM(silver_claims.paid_amount) * 100.0
        / NULLIF(SUM(silver_claims.billed_amount), 0),
        2
      )
    comment: >
      Cash collection rate: total paid / total billed * 100.
      Includes all claim statuses. Industry benchmark: above 90%.

  - name: avg_days_in_ar
    expr: AVG(source.days_outstanding)
    comment: >
      Average number of days a balance has been outstanding.
      Target: below 40 days. Above 60 days indicates a follow-up lag.

  - name: avg_recovery_score
    expr: ROUND(AVG(source.recovery_score), 4)
    comment: >
      Model-predicted probability of collecting the outstanding balance (0.0 to 1.0).
      Declines significantly for buckets beyond 90 days.

  - name: total_billed
    expr: ROUND(SUM(silver_claims.billed_amount), 2)
    comment: "Total amount billed to the payer before adjustments"

  - name: total_paid
    expr: ROUND(SUM(silver_claims.paid_amount), 2)
    comment: "Total amount paid by the payer"

  - name: appeal_rate
    expr: >
      ROUND(
        COUNT(CASE WHEN silver_denials.is_appealed THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN silver_claims.claim_status = 'DENIED' THEN 1 END), 0),
        2
      )
    comment: >
      Percentage of denied claims that were appealed.
      Higher = more aggressive recovery posture.
      If denial_rate is high but appeal_rate is low, revenue is being left on the table.

  - name: appeal_approval_rate
    expr: >
      ROUND(
        COUNT(CASE WHEN silver_denials.appeal_outcome = 'approved' THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN silver_denials.is_appealed THEN 1 END), 0),
        2
      )
    comment: >
      Percentage of filed appeals that were approved (money recovered).
      Target: above 35%. High win rate on a low-appeal denial category = high-opportunity category.

  - name: net_recoverable_amount
    expr: ROUND(SUM(source.balance_amount * source.recovery_score), 2)
    comment: >
      Expected collectible dollars: balance_amount × recovery_score.
      Prioritize accounts with high net_recoverable_amount for follow-up.
$$;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 3 — Test the Metric View
-- MAGIC
-- MAGIC When querying a metric view, wrap measure names in `MEASURE()`.
-- MAGIC This tells Databricks to apply the exact aggregation logic you defined in the YAML.
-- MAGIC Dimensions are queried normally (no wrapper needed).
-- MAGIC
-- MAGIC ```sql
-- MAGIC SELECT
-- MAGIC   dimension_col,                   -- no MEASURE() needed for dimensions
-- MAGIC   MEASURE(my_measure_name)         -- MEASURE() required for measures
-- MAGIC FROM mv_your_view
-- MAGIC GROUP BY dimension_col;
-- MAGIC ```

-- COMMAND ----------

-- 3a. Basic test: denial rate and AR balance by line of business
SELECT
  lob,
  MEASURE(denial_rate)          AS denial_rate_pct,
  MEASURE(collection_rate)      AS collection_rate_pct,
  MEASURE(total_ar_balance)     AS ar_balance,
  MEASURE(record_count)         AS open_ar_records
FROM mv_rcm_finance
GROUP BY lob
ORDER BY MEASURE(denial_rate) DESC;

-- COMMAND ----------

-- 3b. AR aging analysis with recovery context
--     This is the view an AR manager checks weekly.
SELECT
  aging_bucket,
  lob,
  MEASURE(record_count)           AS records,
  MEASURE(total_ar_balance)       AS balance,
  MEASURE(avg_days_in_ar)         AS avg_days,
  MEASURE(avg_recovery_score)     AS recovery_probability,
  MEASURE(net_recoverable_amount) AS expected_collectible
FROM mv_rcm_finance
GROUP BY aging_bucket, lob
ORDER BY
  CASE aging_bucket
    WHEN '0-30'   THEN 1
    WHEN '31-60'  THEN 2
    WHEN '61-90'  THEN 3
    WHEN '91-120' THEN 4
    WHEN '120+'   THEN 5
  END,
  lob;

-- COMMAND ----------

-- 3c. Denial appeal analysis — where is money being recovered?
SELECT
  denial_category,
  carc_code,
  MEASURE(record_count)           AS ar_records,
  MEASURE(denial_rate)            AS denial_rate_pct,
  MEASURE(appeal_rate)            AS pct_appealed,
  MEASURE(appeal_approval_rate)   AS pct_appeals_won,
  MEASURE(total_ar_balance)       AS balance_at_risk
FROM mv_rcm_finance
WHERE denial_category IS NOT NULL
GROUP BY denial_category, carc_code
ORDER BY MEASURE(total_ar_balance) DESC;

-- COMMAND ----------

-- 3d. Monthly trend — denial rate, collection rate, and AR balance
SELECT
  service_month,
  MEASURE(denial_rate)        AS denial_rate_pct,
  MEASURE(collection_rate)    AS collection_rate_pct,
  MEASURE(total_ar_balance)   AS ar_balance,
  MEASURE(record_count)       AS open_claims
FROM mv_rcm_finance
WHERE service_month >= '2024-01-01'
GROUP BY service_month
ORDER BY service_month;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Step 4 — Add to a Genie Space (UI Steps)
-- MAGIC
-- MAGIC After the metric view is created, you're ready to configure the Genie space.
-- MAGIC
-- MAGIC ### A. Create the Genie Space
-- MAGIC 1. Go to **Genie** in the left nav → **New Genie space**
-- MAGIC 2. Name it: `RCM Finance Assistant`
-- MAGIC
-- MAGIC ### B. Add Tables
-- MAGIC Under the **Data** tab → **Add tables**:
-- MAGIC - `silver_claims`
-- MAGIC - `silver_denials`
-- MAGIC - `gold_ar_aging`
-- MAGIC - `gold_kpi_daily`
-- MAGIC
-- MAGIC ### C. Add the Metric View
-- MAGIC Under **Data** tab → **Add metric views** → select `mv_rcm_finance`
-- MAGIC
-- MAGIC > **Why add both raw tables AND the metric view?**
-- MAGIC > The metric view handles pre-defined measures (denial_rate, collection_rate).
-- MAGIC > Raw tables let Genie answer ad-hoc questions using columns not in the view.
-- MAGIC
-- MAGIC ### D. Add SQL Instructions
-- MAGIC Under the **Instructions** tab, add these hints:
-- MAGIC ```
-- MAGIC - "AR" or "accounts receivable" means the gold_ar_aging table or the total_ar_balance measure.
-- MAGIC - "Denial rate" means denied claims / total claims * 100. Use the denial_rate measure.
-- MAGIC - "Collection rate" means paid / billed * 100. Use the collection_rate measure.
-- MAGIC - For trend questions (over time, by month, monthly), group by DATE_TRUNC('month', service_date_dt).
-- MAGIC - Always filter to the last 12 months unless the user specifies a different time range.
-- MAGIC - "High-risk AR" means aging_bucket = '120+' AND recovery_score < 0.20.
-- MAGIC - When comparing LOBs, use MA = Medicare Advantage, MCD = Medicaid, COM = Commercial.
-- MAGIC ```
-- MAGIC
-- MAGIC ### E. Test It
-- MAGIC Ask these questions:
-- MAGIC - *"What is the denial rate for prior auth claims by state?"*
-- MAGIC - *"Show me AR aging trend for Medicare Advantage in 2024"*
-- MAGIC - *"Which providers have the highest at-risk AR balance?"*
-- MAGIC - *"Compare collection rates between MA and Medicaid by month"*

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## 📝 TODOs — Try These Yourself
-- MAGIC
-- MAGIC **TODO 12** — Add a `is_high_value_risk` dimension to the metric view.
-- MAGIC A record is high-value-risk when `balance_amount > 10000 AND aging_bucket = '120+'`.
-- MAGIC ```yaml
-- MAGIC   - name: is_high_value_risk
-- MAGIC     expr: "CASE WHEN source.balance_amount > 10000 AND source.aging_bucket = '120+' THEN true ELSE false END"
-- MAGIC     comment: "True when balance exceeds $10K and is over 120 days outstanding"
-- MAGIC ```
-- MAGIC After adding it, re-run query 3a and GROUP BY `is_high_value_risk`.
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC **TODO 13** — Verify that `net_recoverable_amount` is already in the metric view.
-- MAGIC Run this query and confirm the results make sense:
-- MAGIC ```sql
-- MAGIC SELECT state, MEASURE(total_ar_balance), MEASURE(net_recoverable_amount),
-- MAGIC        ROUND(MEASURE(net_recoverable_amount) / MEASURE(total_ar_balance) * 100, 1) AS recovery_pct
-- MAGIC FROM mv_rcm_finance
-- MAGIC GROUP BY state ORDER BY MEASURE(net_recoverable_amount) DESC;
-- MAGIC ```
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC **TODO 14** — Write a query using `MEASURE()` that shows:
-- MAGIC `denial_rate`, `collection_rate`, and `total_ar_balance`
-- MAGIC broken down by `state` and `lob` for 2024 only.
-- MAGIC Filter using `WHERE service_year = 2024`.
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC **TODO 15** — After adding the metric view to your Genie space:
-- MAGIC Ask: *"What is the total AR balance for MA in the 0-30 aging bucket?"*
-- MAGIC Scroll down in Genie's answer to see the SQL it generated.
-- MAGIC Does it reference `mv_rcm_finance`? Does it use `MEASURE()`?
