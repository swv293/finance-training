# Databricks notebook source
# MAGIC %md
# MAGIC # Solutions — All 24 TODOs
# MAGIC **Finance Team · Databricks Workshop**
# MAGIC
# MAGIC ---
# MAGIC
# MAGIC This notebook contains working solutions to every TODO across the workshop.
# MAGIC Use it **after** attempting each TODO yourself — solutions are most useful
# MAGIC when you have a specific question about why your version didn't work.
# MAGIC
# MAGIC | TODOs | Source Notebook | Topic |
# MAGIC |---|---|---|
# MAGIC | 1–3 | `00_setup_and_ingestion.py` | Delta Lake table operations |
# MAGIC | 4–6 | `01_sql_basics.sql` | Joins, aggregation, safe division |
# MAGIC | 7–9 | `02_advanced_analytics.sql` | CTEs, window functions |
# MAGIC | 10–11 | `02b_genie_code_examples.sql` | Genie Code prompt writing |
# MAGIC | 12–15 | `03_metric_views.sql` | Metric view YAML, MEASURE() |
# MAGIC | 16–19 | Dashboard UI | Chart types, filters, sharing |
# MAGIC | 20–22 | Genie Space UI | Instructions, trusted assets |
# MAGIC | 23–24 | `05_workflow_demo.py` | Workflow tasks, timeouts |

# COMMAND ----------

# MAGIC %md
# MAGIC ## Setup — Set Your Schema Before Running Anything

# COMMAND ----------

# MAGIC %sql
# MAGIC USE CATALOG main;
# MAGIC USE SCHEMA finance_training_firstname;   -- ← change this to your name

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC # TODOs 1–3 · Delta Lake Table Operations
# MAGIC *Source: `00_setup_and_ingestion.py`*

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 1
# MAGIC **Question:** The `ALTER TABLE` above added `load_timestamp` to `bronze_claims`.
# MAGIC Do the same for `bronze_members` — add a `created_at TIMESTAMP` column and backfill it.
# MAGIC
# MAGIC **Concepts tested:** `ALTER TABLE ... ADD COLUMN`, `UPDATE`, `CURRENT_TIMESTAMP()`

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Step 1: add the column (starts as NULL for all existing rows)
# MAGIC ALTER TABLE bronze_members ADD COLUMN created_at TIMESTAMP;
# MAGIC
# MAGIC -- Step 2: backfill with the current timestamp
# MAGIC -- In production you'd use the actual load time; here we use now() as a stand-in
# MAGIC UPDATE bronze_members
# MAGIC SET created_at = CURRENT_TIMESTAMP()
# MAGIC WHERE created_at IS NULL;

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Verify: check the column was added and is populated
# MAGIC SELECT member_id, plan_type, created_at
# MAGIC FROM bronze_members
# MAGIC LIMIT 5;

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Bonus: check DESCRIBE HISTORY to see both operations recorded
# MAGIC DESCRIBE HISTORY bronze_members;

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 2
# MAGIC **Question:** Use `display()` to show the **top 10 members by total billed amount**.
# MAGIC *(Hint: use a `%sql` cell with GROUP BY and ORDER BY)*
# MAGIC
# MAGIC **Concepts tested:** Aggregation with `SUM()`, `GROUP BY`, `ORDER BY ... DESC`, `LIMIT`

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Top 10 members by total billed amount
# MAGIC -- We join bronze_members to get the member's state and plan type for context
# MAGIC SELECT
# MAGIC   c.member_id,
# MAGIC   m.state,
# MAGIC   m.plan_type,
# MAGIC   m.lob,
# MAGIC   COUNT(c.claim_id)               AS total_claims,
# MAGIC   ROUND(SUM(c.billed_amount), 2)  AS total_billed,
# MAGIC   ROUND(SUM(c.paid_amount), 2)    AS total_paid,
# MAGIC   ROUND(SUM(c.billed_amount) - SUM(c.paid_amount), 2) AS total_outstanding
# MAGIC FROM silver_claims c
# MAGIC JOIN bronze_members m ON c.member_id = m.member_id
# MAGIC GROUP BY c.member_id, m.state, m.plan_type, m.lob
# MAGIC ORDER BY total_billed DESC
# MAGIC LIMIT 10;

# COMMAND ----------

# MAGIC %md
# MAGIC > **Why join to `bronze_members`?**
# MAGIC > `silver_claims` has `member_id` but not `state` or `plan_type` directly.
# MAGIC > Adding member context makes the result actionable — you can see *who* the high-cost members are
# MAGIC > and which plan type they're on.

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 3
# MAGIC **Question:** How many **distinct providers** are in your dataset?
# MAGIC Write a SQL cell that returns the count, broken down by `specialty`.
# MAGIC
# MAGIC **Concepts tested:** `COUNT(DISTINCT ...)`, `GROUP BY`, ordering by count

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Provider count by specialty, ordered from most to fewest
# MAGIC SELECT
# MAGIC   specialty,
# MAGIC   COUNT(DISTINCT provider_id)  AS provider_count,
# MAGIC   COUNT(CASE WHEN is_network   THEN 1 END) AS in_network_count,
# MAGIC   COUNT(CASE WHEN NOT is_network THEN 1 END) AS out_of_network_count,
# MAGIC   -- % of providers in this specialty that are in-network
# MAGIC   ROUND(
# MAGIC     COUNT(CASE WHEN is_network THEN 1 END) * 100.0
# MAGIC     / COUNT(DISTINCT provider_id),
# MAGIC     1
# MAGIC   )                            AS in_network_pct
# MAGIC FROM bronze_providers
# MAGIC GROUP BY specialty
# MAGIC ORDER BY provider_count DESC;

# COMMAND ----------

# MAGIC %md
# MAGIC > **Why add the in-network breakdown?**
# MAGIC > The question only asks for a count by specialty, but network status is a key dimension
# MAGIC > for contract negotiations. A specialty with 80% out-of-network providers is a red flag.
# MAGIC > In real work, always add one layer of context to a count query.

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC # TODOs 4–6 · SQL Basics
# MAGIC *Source: `01_sql_basics.sql`*

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 4
# MAGIC **Question:** Find the average days-to-payment for PAID claims, broken down by claim type.
# MAGIC Expected columns: `claim_type`, `avg_days_to_submit`, `claim_count`
# MAGIC
# MAGIC **Concepts tested:** `WHERE` filtering, `AVG()`, `DATEDIFF()`, `GROUP BY`

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Average days from service date to submit date for PAID claims only
# MAGIC -- days_to_submit is already pre-computed in silver_claims, but we show the derivation too
# MAGIC SELECT
# MAGIC   claim_type,
# MAGIC   COUNT(claim_id)                                AS claim_count,
# MAGIC   ROUND(AVG(days_to_submit), 1)                  AS avg_days_to_submit,
# MAGIC   MIN(days_to_submit)                            AS min_days,
# MAGIC   MAX(days_to_submit)                            AS max_days,
# MAGIC   -- Flag claim types where avg submission time exceeds 30 days (timely filing risk)
# MAGIC   CASE
# MAGIC     WHEN AVG(days_to_submit) > 30 THEN '⚠ Timely filing risk'
# MAGIC     ELSE '✓ OK'
# MAGIC   END                                            AS timely_filing_status
# MAGIC FROM silver_claims
# MAGIC WHERE claim_status = 'PAID'
# MAGIC GROUP BY claim_type
# MAGIC ORDER BY avg_days_to_submit DESC;

# COMMAND ----------

# MAGIC %md
# MAGIC > **Why filter to PAID only?**
# MAGIC > Days-to-submit for denied or pending claims is less meaningful — those claims may still be
# MAGIC > in process. Filtering to PAID gives you a clean baseline: claims that made it through,
# MAGIC > how fast were they submitted?

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 5
# MAGIC **Question:** For each line of business, find the **top denial category** (the one with the most denials).
# MAGIC Use a CTE with `RANK()` to find the single top category per LOB.
# MAGIC
# MAGIC **Concepts tested:** CTEs, `RANK() OVER (PARTITION BY ...)`, filtering on a rank column

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Step 1: count denials per LOB + category
# MAGIC -- Step 2: rank categories within each LOB (highest count = rank 1)
# MAGIC -- Step 3: keep only rank 1 (the top category per LOB)
# MAGIC WITH lob_denial AS (
# MAGIC   SELECT
# MAGIC     lob,
# MAGIC     denial_category,
# MAGIC     COUNT(*)  AS denial_count
# MAGIC   FROM silver_claims
# MAGIC   WHERE claim_status = 'DENIED'
# MAGIC   GROUP BY lob, denial_category
# MAGIC ),
# MAGIC ranked AS (
# MAGIC   SELECT
# MAGIC     *,
# MAGIC     RANK() OVER (
# MAGIC       PARTITION BY lob
# MAGIC       ORDER BY denial_count DESC
# MAGIC     ) AS rk
# MAGIC   FROM lob_denial
# MAGIC )
# MAGIC SELECT
# MAGIC   lob,
# MAGIC   denial_category  AS top_denial_category,
# MAGIC   denial_count
# MAGIC FROM ranked
# MAGIC WHERE rk = 1
# MAGIC ORDER BY denial_count DESC;

# COMMAND ----------

# MAGIC %md
# MAGIC > **Why use RANK() instead of just MAX()?**
# MAGIC > `MAX(denial_count)` tells you the highest count but not which category it belongs to.
# MAGIC > `RANK()` assigns a position to each row within each group, so you can filter to `rk = 1`
# MAGIC > and get the full row — category name, count, and LOB — in one query.
# MAGIC >
# MAGIC > **Edge case:** If two categories tie for first, `RANK()` returns both as `rk = 1`.
# MAGIC > Use `ROW_NUMBER()` instead if you want exactly one row per LOB regardless of ties.

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 6
# MAGIC **Question:** Calculate the **out-of-network (OON) claim rate by state**.
# MAGIC Join `silver_claims` to `bronze_providers` and show: state, total_claims, oon_claims, oon_pct.
# MAGIC
# MAGIC **Concepts tested:** JOIN, `COUNT(CASE WHEN ...)`, safe percentage calculation

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Out-of-network rate by state
# MAGIC -- is_network = FALSE means the provider is out-of-network for this claim
# MAGIC SELECT
# MAGIC   c.state,
# MAGIC   COUNT(c.claim_id)                                             AS total_claims,
# MAGIC   COUNT(CASE WHEN NOT p.is_network THEN 1 END)                 AS oon_claims,
# MAGIC   ROUND(
# MAGIC     COUNT(CASE WHEN NOT p.is_network THEN 1 END) * 100.0
# MAGIC     / NULLIF(COUNT(c.claim_id), 0),
# MAGIC     2
# MAGIC   )                                                             AS oon_pct,
# MAGIC   -- Also show in-network count for completeness
# MAGIC   COUNT(CASE WHEN p.is_network THEN 1 END)                     AS in_network_claims
# MAGIC FROM silver_claims c
# MAGIC JOIN bronze_providers p ON c.provider_id = p.provider_id
# MAGIC GROUP BY c.state
# MAGIC ORDER BY oon_pct DESC;

# COMMAND ----------

# MAGIC %md
# MAGIC > **The `NULLIF` pattern:** `COUNT(*) / NULLIF(COUNT(*), 0)` returns NULL instead of
# MAGIC > dividing by zero when a state has no claims. This prevents a runtime error.
# MAGIC > Databricks SQL does not automatically handle divide-by-zero — you must guard it explicitly.

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC # TODOs 7–9 · Advanced Analytics
# MAGIC *Source: `02_advanced_analytics.sql`*

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 7
# MAGIC **Question:** In the AR aging CTE, add a flag for records that are BOTH high-value AND critical risk.
# MAGIC A record is "critical" when: `balance_amount > 10000` AND `aging_bucket = '120+'` AND `recovery_score < 0.20`.
# MAGIC Add a column called `is_critical`. How many critical records exist per state?
# MAGIC
# MAGIC **Concepts tested:** Multi-condition `CASE WHEN`, CTE modification, aggregating a boolean flag

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Full solution: rebuild the at_risk CTE with is_critical added
# MAGIC WITH base AS (
# MAGIC   SELECT
# MAGIC     ar.claim_id,
# MAGIC     ar.member_id,
# MAGIC     ar.provider_id,
# MAGIC     ar.aging_bucket,
# MAGIC     ar.balance_amount,
# MAGIC     ar.recovery_score,
# MAGIC     ar.days_outstanding,
# MAGIC     ar.lob,
# MAGIC     c.state,
# MAGIC     p.specialty
# MAGIC   FROM gold_ar_aging ar
# MAGIC   JOIN silver_claims   c ON ar.claim_id   = c.claim_id
# MAGIC   JOIN bronze_providers p ON ar.provider_id = p.provider_id
# MAGIC ),
# MAGIC at_risk AS (
# MAGIC   SELECT
# MAGIC     *,
# MAGIC     CASE
# MAGIC       WHEN aging_bucket IN ('91-120', '120+') AND recovery_score < 0.50
# MAGIC       THEN TRUE ELSE FALSE
# MAGIC     END                                                        AS is_at_risk,
# MAGIC
# MAGIC     -- ── TODO 7 solution ────────────────────────────────────────
# MAGIC     -- "Critical" = high value + oldest bucket + very low recovery probability
# MAGIC     CASE
# MAGIC       WHEN balance_amount > 10000
# MAGIC        AND aging_bucket   = '120+'
# MAGIC        AND recovery_score < 0.20
# MAGIC       THEN TRUE ELSE FALSE
# MAGIC     END                                                        AS is_critical
# MAGIC     -- ────────────────────────────────────────────────────────────
# MAGIC   FROM base
# MAGIC )
# MAGIC -- Count critical records per state — the collections team's priority list
# MAGIC SELECT
# MAGIC   state,
# MAGIC   COUNT(*)                                         AS total_at_risk,
# MAGIC   COUNT(CASE WHEN is_critical THEN 1 END)         AS critical_count,
# MAGIC   ROUND(SUM(CASE WHEN is_critical THEN balance_amount ELSE 0 END), 2) AS critical_balance
# MAGIC FROM at_risk
# MAGIC WHERE is_at_risk
# MAGIC GROUP BY state
# MAGIC ORDER BY critical_balance DESC;

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 8
# MAGIC **Question:** In the provider ranking query, add a column showing each provider's denial rate
# MAGIC compared to the **average denial rate for their state and specialty combined**.
# MAGIC
# MAGIC **Concepts tested:** `AVG() OVER (PARTITION BY multiple columns)`, deviation from group average

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Provider denial rate vs state+specialty average
# MAGIC -- The window function AVG() OVER computes the average across all providers
# MAGIC -- sharing the same state AND specialty — without collapsing the result set
# MAGIC WITH provider_metrics AS (
# MAGIC   SELECT
# MAGIC     c.provider_id,
# MAGIC     p.provider_name,
# MAGIC     p.specialty,
# MAGIC     c.state,
# MAGIC     p.provider_tier,
# MAGIC     COUNT(c.claim_id)                                              AS total_claims,
# MAGIC     COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END)         AS denied_claims,
# MAGIC     ROUND(
# MAGIC       COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END) * 100.0
# MAGIC       / NULLIF(COUNT(c.claim_id), 0),
# MAGIC       2
# MAGIC     )                                                              AS denial_rate_pct
# MAGIC   FROM silver_claims c
# MAGIC   JOIN bronze_providers p ON c.provider_id = p.provider_id
# MAGIC   GROUP BY c.provider_id, p.provider_name, p.specialty, c.state, p.provider_tier
# MAGIC   HAVING COUNT(c.claim_id) >= 10
# MAGIC )
# MAGIC SELECT
# MAGIC   provider_name,
# MAGIC   specialty,
# MAGIC   state,
# MAGIC   provider_tier,
# MAGIC   total_claims,
# MAGIC   denial_rate_pct,
# MAGIC
# MAGIC   -- ── TODO 8 solution ────────────────────────────────────────────────────
# MAGIC   -- Average denial rate across all providers in the same state + specialty
# MAGIC   ROUND(
# MAGIC     AVG(denial_rate_pct) OVER (PARTITION BY state, specialty),
# MAGIC     2
# MAGIC   )                                                                AS state_specialty_avg_denial_rate,
# MAGIC
# MAGIC   -- Deviation: positive = this provider is worse than peers; negative = better
# MAGIC   ROUND(
# MAGIC     denial_rate_pct
# MAGIC     - AVG(denial_rate_pct) OVER (PARTITION BY state, specialty),
# MAGIC     2
# MAGIC   )                                                                AS deviation_from_peer_avg,
# MAGIC   -- ────────────────────────────────────────────────────────────────────────
# MAGIC
# MAGIC   CASE
# MAGIC     WHEN denial_rate_pct > AVG(denial_rate_pct) OVER (PARTITION BY state, specialty) + 2
# MAGIC     THEN '⚠ Outlier — review'
# MAGIC     ELSE '→ Within peer range'
# MAGIC   END                                                              AS peer_comparison
# MAGIC FROM provider_metrics
# MAGIC ORDER BY deviation_from_peer_avg DESC;

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 9
# MAGIC **Question:** Find months where the **7-day rolling collection rate dropped below 88%**.
# MAGIC Use `gold_kpi_daily`. Show month, average rolling collection rate for that month, and a flag.
# MAGIC
# MAGIC **Concepts tested:** Nesting a window function inside an aggregate, `DATE_TRUNC`, threshold flagging

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Months where the average 7-day rolling collection rate fell below 88%
# MAGIC --
# MAGIC -- Pattern: compute the rolling rate per day first, then aggregate by month.
# MAGIC -- You cannot nest a window function directly inside AVG() in one step —
# MAGIC -- wrap the window in a CTE, then aggregate in the outer query.
# MAGIC WITH daily_rolling AS (
# MAGIC   SELECT
# MAGIC     kpi_date,
# MAGIC     collection_rate,
# MAGIC     -- 7-day rolling average (current day + 6 prior days)
# MAGIC     AVG(collection_rate) OVER (
# MAGIC       ORDER BY kpi_date
# MAGIC       ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
# MAGIC     )                                                      AS rolling_7d_collection_rate
# MAGIC   FROM gold_kpi_daily
# MAGIC ),
# MAGIC monthly_avg AS (
# MAGIC   SELECT
# MAGIC     DATE_TRUNC('month', CAST(kpi_date AS DATE))            AS month,
# MAGIC     ROUND(AVG(rolling_7d_collection_rate), 4)              AS avg_monthly_rolling_cr,
# MAGIC     MIN(rolling_7d_collection_rate)                        AS worst_day_in_month,
# MAGIC     COUNT(CASE WHEN rolling_7d_collection_rate < 0.88 THEN 1 END) AS days_below_threshold
# MAGIC   FROM daily_rolling
# MAGIC   GROUP BY DATE_TRUNC('month', CAST(kpi_date AS DATE))
# MAGIC )
# MAGIC SELECT
# MAGIC   month,
# MAGIC   ROUND(avg_monthly_rolling_cr * 100, 2)  AS avg_rolling_cr_pct,
# MAGIC   ROUND(worst_day_in_month * 100, 2)       AS worst_day_pct,
# MAGIC   days_below_threshold,
# MAGIC   CASE
# MAGIC     WHEN avg_monthly_rolling_cr < 0.88 THEN '🔴 Below threshold — investigate'
# MAGIC     WHEN worst_day_in_month     < 0.88 THEN '🟡 Dipped below threshold at least once'
# MAGIC     ELSE                                     '🟢 OK'
# MAGIC   END                                       AS status
# MAGIC FROM monthly_avg
# MAGIC ORDER BY month;

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC # TODOs 10–11 · Genie Code
# MAGIC *Source: `02b_genie_code_examples.sql`*
# MAGIC
# MAGIC These TODOs are about **writing prompts** and evaluating the SQL Genie Code generates.
# MAGIC There is no single "correct" SQL — the goal is to assess whether what Genie produces is valid.

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 10
# MAGIC **Question:** Use Genie Code to write: *"Monthly collection rate trend for Medicare Advantage (MA)
# MAGIC only in 2024. Include the previous month, month-over-month change in percentage points,
# MAGIC and a column showing whether it improved, worsened, or stayed flat."*
# MAGIC
# MAGIC **What to check in the generated SQL:**
# MAGIC 1. Does it filter `lob = 'MA'`?
# MAGIC 2. Does it use `LAG()` with `PARTITION BY lob ORDER BY service_month`?
# MAGIC 3. Does it handle NULL for the first month (no prior month)?

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Reference solution — compare to what Genie Code generated for you
# MAGIC WITH ma_monthly AS (
# MAGIC   SELECT
# MAGIC     service_month,
# MAGIC     lob,
# MAGIC     COUNT(claim_id)                                      AS total_claims,
# MAGIC     ROUND(
# MAGIC       SUM(paid_amount) * 100.0
# MAGIC       / NULLIF(SUM(billed_amount), 0),
# MAGIC       4
# MAGIC     )                                                    AS collection_rate_pct
# MAGIC   FROM silver_claims
# MAGIC   WHERE lob = 'MA'
# MAGIC     AND service_month BETWEEN '2024-01-01' AND '2024-12-01'
# MAGIC   GROUP BY service_month, lob
# MAGIC )
# MAGIC SELECT
# MAGIC   service_month,
# MAGIC   total_claims,
# MAGIC   collection_rate_pct,
# MAGIC   LAG(collection_rate_pct, 1) OVER (
# MAGIC     PARTITION BY lob ORDER BY service_month
# MAGIC   )                                                      AS prev_month_rate,
# MAGIC   ROUND(
# MAGIC     collection_rate_pct
# MAGIC     - LAG(collection_rate_pct, 1) OVER (PARTITION BY lob ORDER BY service_month),
# MAGIC     4
# MAGIC   )                                                      AS mom_change_ppts,
# MAGIC   CASE
# MAGIC     WHEN collection_rate_pct
# MAGIC          > LAG(collection_rate_pct, 1) OVER (PARTITION BY lob ORDER BY service_month)
# MAGIC     THEN '↑ Improved'
# MAGIC     WHEN collection_rate_pct
# MAGIC          < LAG(collection_rate_pct, 1) OVER (PARTITION BY lob ORDER BY service_month)
# MAGIC     THEN '↓ Worsened'
# MAGIC     WHEN LAG(collection_rate_pct, 1) OVER (PARTITION BY lob ORDER BY service_month) IS NULL
# MAGIC     THEN '— First month'
# MAGIC     ELSE '→ Flat'
# MAGIC   END                                                    AS direction
# MAGIC FROM ma_monthly
# MAGIC ORDER BY service_month;

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 11
# MAGIC **Question:** Starting from the scorecard query in `02b_genie_code_examples.sql`, use Genie Code
# MAGIC to add a year-over-year comparison showing each provider's composite score in 2024 vs 2025.
# MAGIC Flag whether their overall ranking improved or worsened.
# MAGIC
# MAGIC **What to check in the generated SQL:**
# MAGIC 1. Does it split data by year (filter or self-join)?
# MAGIC 2. Does it handle providers who have claims in only one year?
# MAGIC 3. How does it define "improved" — lower composite score, or higher rank?

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Reference solution — YoY provider composite score comparison
# MAGIC -- Pattern: build the scorecard CTE for each year separately, then join on provider_id
# MAGIC WITH provider_yearly AS (
# MAGIC   SELECT
# MAGIC     c.provider_id,
# MAGIC     p.provider_name,
# MAGIC     p.specialty,
# MAGIC     YEAR(c.service_month)                                          AS claim_year,
# MAGIC     COUNT(c.claim_id)                                              AS total_claims,
# MAGIC     ROUND(
# MAGIC       COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END) * 100.0
# MAGIC       / NULLIF(COUNT(c.claim_id), 0), 2)                          AS denial_rate_pct,
# MAGIC     ROUND(
# MAGIC       SUM(c.paid_amount) * 100.0
# MAGIC       / NULLIF(SUM(c.billed_amount), 0), 2)                       AS collection_rate_pct
# MAGIC   FROM silver_claims c
# MAGIC   JOIN bronze_providers p ON c.provider_id = p.provider_id
# MAGIC   WHERE YEAR(c.service_month) IN (2024, 2025)
# MAGIC   GROUP BY c.provider_id, p.provider_name, p.specialty, YEAR(c.service_month)
# MAGIC   HAVING COUNT(c.claim_id) >= 20
# MAGIC ),
# MAGIC with_ranks AS (
# MAGIC   SELECT
# MAGIC     *,
# MAGIC     RANK() OVER (PARTITION BY specialty, claim_year ORDER BY denial_rate_pct ASC)    AS denial_rank,
# MAGIC     RANK() OVER (PARTITION BY specialty, claim_year ORDER BY collection_rate_pct DESC) AS collection_rank,
# MAGIC     RANK() OVER (PARTITION BY specialty, claim_year ORDER BY total_claims DESC)       AS volume_rank,
# MAGIC     COUNT(*) OVER (PARTITION BY specialty, claim_year)                               AS peer_count
# MAGIC   FROM provider_yearly
# MAGIC ),
# MAGIC with_composite AS (
# MAGIC   SELECT *,
# MAGIC     ROUND((denial_rank + collection_rank + volume_rank) / 3.0, 2)  AS composite_score
# MAGIC   FROM with_ranks
# MAGIC )
# MAGIC -- Pivot: one row per provider showing 2024 and 2025 side by side
# MAGIC SELECT
# MAGIC   COALESCE(y24.provider_name, y25.provider_name)  AS provider_name,
# MAGIC   COALESCE(y24.specialty,     y25.specialty)       AS specialty,
# MAGIC   y24.composite_score                              AS score_2024,
# MAGIC   y25.composite_score                              AS score_2025,
# MAGIC   y24.denial_rate_pct                              AS denial_rate_2024,
# MAGIC   y25.denial_rate_pct                              AS denial_rate_2025,
# MAGIC   CASE
# MAGIC     WHEN y24.composite_score IS NULL               THEN '🆕 New in 2025'
# MAGIC     WHEN y25.composite_score IS NULL               THEN '❌ No 2025 data'
# MAGIC     WHEN y25.composite_score < y24.composite_score THEN '↑ Improved'
# MAGIC     WHEN y25.composite_score > y24.composite_score THEN '↓ Worsened'
# MAGIC     ELSE                                                '→ Flat'
# MAGIC   END                                              AS yoy_trend
# MAGIC FROM with_composite y24
# MAGIC FULL OUTER JOIN with_composite y25
# MAGIC   ON  y24.provider_id = y25.provider_id
# MAGIC   AND y24.specialty   = y25.specialty
# MAGIC   AND y24.claim_year  = 2024
# MAGIC   AND y25.claim_year  = 2025
# MAGIC WHERE y24.claim_year = 2024 OR y24.claim_year IS NULL
# MAGIC ORDER BY specialty, COALESCE(y24.composite_score, y25.composite_score);

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC # TODOs 12–15 · Metric Views
# MAGIC *Source: `03_metric_views.sql`*

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 12
# MAGIC **Question:** Add a dimension called `is_high_value_risk` to the metric view.
# MAGIC It should be `true` when `balance_amount > 10000` AND `aging_bucket = '120+'`.
# MAGIC
# MAGIC **Concepts tested:** Metric view YAML `dimensions` block, `expr` for derived dimensions

# COMMAND ----------

# MAGIC %sql
# MAGIC -- The dimension block to add inside the WITH METRICS LANGUAGE YAML section of mv_rcm_finance
# MAGIC -- Add this under the `dimensions:` key, after the existing `denial_related` dimension
# MAGIC
# MAGIC -- dimensions:
# MAGIC --   ...
# MAGIC --   - name: is_high_value_risk
# MAGIC --     expr: "CASE WHEN source.balance_amount > 10000 AND source.aging_bucket = '120+' THEN true ELSE false END"
# MAGIC --     type: boolean
# MAGIC --     comment: "True when balance exceeds $10K and claim has been outstanding 120+ days"
# MAGIC
# MAGIC -- After adding it, re-run the CREATE OR REPLACE METRIC VIEW statement,
# MAGIC -- then test it with:
# MAGIC SELECT
# MAGIC   is_high_value_risk,
# MAGIC   MEASURE(record_count)       AS claims,
# MAGIC   MEASURE(total_ar_balance)   AS total_balance
# MAGIC FROM mv_rcm_finance
# MAGIC GROUP BY is_high_value_risk;

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 13
# MAGIC **Question:** Verify that `net_recoverable_amount` is already in the metric view.
# MAGIC Run a query using `MEASURE(net_recoverable_amount)` grouped by `aging_bucket`.
# MAGIC Does the result match `balance_amount × recovery_score`?
# MAGIC
# MAGIC **Concepts tested:** Reading metric view definitions, verifying measure calculations

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Test net_recoverable_amount against a manual calculation
# MAGIC -- Both columns should be very close (floating-point rounding may cause tiny differences)
# MAGIC SELECT
# MAGIC   aging_bucket,
# MAGIC   MEASURE(net_recoverable_amount)                  AS metric_view_recoverable,
# MAGIC   -- Manual calculation to verify:
# MAGIC   ROUND(SUM(balance_amount * recovery_score), 2)  AS manual_calculation
# MAGIC FROM mv_rcm_finance
# MAGIC -- Note: the manual calc references the underlying table for cross-check
# MAGIC -- In practice you'd query mv_rcm_finance only — this is just for verification
# MAGIC GROUP BY aging_bucket
# MAGIC ORDER BY aging_bucket;

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Simpler verification: just confirm net_recoverable_amount works
# MAGIC SELECT
# MAGIC   aging_bucket,
# MAGIC   lob,
# MAGIC   MEASURE(net_recoverable_amount)   AS expected_collections,
# MAGIC   MEASURE(total_ar_balance)         AS total_ar,
# MAGIC   ROUND(
# MAGIC     MEASURE(net_recoverable_amount) * 100.0
# MAGIC     / NULLIF(MEASURE(total_ar_balance), 0),
# MAGIC     2
# MAGIC   )                                 AS recovery_rate_pct
# MAGIC FROM mv_rcm_finance
# MAGIC GROUP BY aging_bucket, lob
# MAGIC ORDER BY aging_bucket, lob;

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 14
# MAGIC **Question:** Write a query using `MEASURE()` that shows denial rate, collection rate,
# MAGIC and total AR balance by state and LOB, filtered to 2024, ordered by total AR descending.
# MAGIC
# MAGIC **Concepts tested:** Multi-measure `MEASURE()` queries, `WHERE` on dimensions, `ORDER BY` with `MEASURE()`

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   state,
# MAGIC   lob,
# MAGIC   MEASURE(denial_rate)          AS denial_rate_pct,
# MAGIC   MEASURE(collection_rate)      AS collection_rate_pct,
# MAGIC   MEASURE(total_ar_balance)     AS total_ar_balance,
# MAGIC   MEASURE(avg_recovery_score)   AS avg_recovery_score,
# MAGIC   MEASURE(record_count)         AS claim_count
# MAGIC FROM mv_rcm_finance
# MAGIC WHERE service_year = 2024
# MAGIC GROUP BY state, lob
# MAGIC ORDER BY MEASURE(total_ar_balance) DESC;

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 15
# MAGIC **Question:** After adding `mv_rcm_finance` to your Genie space as a trusted asset,
# MAGIC ask Genie: *"What is the total AR balance for Medicare Advantage in the 0-30 day bucket?"*
# MAGIC
# MAGIC **What Genie should generate** (reference SQL to compare against):

# COMMAND ----------

# MAGIC %sql
# MAGIC -- The SQL Genie should produce — verify your Genie answer matches this result
# MAGIC SELECT
# MAGIC   lob,
# MAGIC   aging_bucket,
# MAGIC   MEASURE(total_ar_balance)   AS total_ar_balance
# MAGIC FROM mv_rcm_finance
# MAGIC WHERE lob          = 'MA'
# MAGIC   AND aging_bucket = '0-30'
# MAGIC GROUP BY lob, aging_bucket;

# COMMAND ----------

# MAGIC %md
# MAGIC > **If Genie's number doesn't match:** Check whether Genie is querying `mv_rcm_finance`
# MAGIC > or the raw `gold_ar_aging` table. Genie uses metric views when they are added as trusted assets.
# MAGIC > If it's not using the metric view, open Genie space settings → Trusted Assets → confirm
# MAGIC > `mv_rcm_finance` is listed. If it is listed but Genie still queries the raw table,
# MAGIC > add a SQL instruction: *"Always use mv_rcm_finance for AR balance and denial rate questions."*

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC # TODOs 16–19 · Dashboard
# MAGIC *Source: Dashboard UI — no SQL to run here*
# MAGIC
# MAGIC These are UI configuration steps. Follow the instructions below in the Databricks Dashboard editor.

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 16 — Widget 5: Collection Rate Trend with Reference Lines
# MAGIC
# MAGIC **Steps:**
# MAGIC 1. In your Finance KPI Dashboard, click **+ Add widget**
# MAGIC 2. Select **Line chart**
# MAGIC 3. Dataset: `ds_kpi_trend`
# MAGIC 4. X-axis: `kpi_date`
# MAGIC 5. Y-axis: `rolling_7d_collection_rate`
# MAGIC 6. Title: *"7-Day Rolling Collection Rate"*
# MAGIC
# MAGIC **Adding the reference lines:**
# MAGIC 7. In the chart configuration panel, scroll to **Reference lines**
# MAGIC 8. Click **+ Add reference line**
# MAGIC    - Label: `Target (90%)`
# MAGIC    - Value: `0.90`
# MAGIC    - Color: Green
# MAGIC 9. Click **+ Add reference line** again
# MAGIC    - Label: `Alert threshold (88%)`
# MAGIC    - Value: `0.88`
# MAGIC    - Color: Red
# MAGIC
# MAGIC **How to verify:** Any month where the line dips below the red reference line is a period
# MAGIC that should appear in your TODO 9 query results.

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 17 — Enable Cross-Filtering
# MAGIC
# MAGIC **Steps:**
# MAGIC 1. In the dashboard, click the **gear icon** (top right of the canvas, or dashboard Settings)
# MAGIC 2. Find **Cross-filtering** → toggle to **Enabled**
# MAGIC 3. Save
# MAGIC
# MAGIC **Test it:**
# MAGIC - Click a bar in the Denial Category chart (Widget 2)
# MAGIC - All other widgets connected to datasets that share the same dimension should filter
# MAGIC - Click the same bar again to deselect (reset all widgets)
# MAGIC
# MAGIC **If cross-filtering doesn't work:** The widgets must share at least one common dimension
# MAGIC (e.g., `lob`, `state`). Check that both datasets include the dimension you clicked on.

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 18 — Auto-Refresh Schedule
# MAGIC
# MAGIC **Steps:**
# MAGIC 1. Dashboard toolbar → click **Refresh** (the clock icon)
# MAGIC 2. Select **Schedule**
# MAGIC 3. Set frequency: **Daily**
# MAGIC 4. Set time: **7:00 AM** (so it's ready when the team arrives)
# MAGIC 5. Timezone: your local timezone
# MAGIC 6. Click **Save**
# MAGIC
# MAGIC **To change the time to 7:00 AM exactly:**
# MAGIC In the schedule dialog, look for the time picker — enter `07:00`.
# MAGIC Some workspace versions use a cron expression: `0 7 * * *` (minute=0, hour=7, every day).

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 19 — Share as Viewer
# MAGIC
# MAGIC **Steps:**
# MAGIC 1. Top right of the dashboard → click **Share**
# MAGIC 2. In the "Add people or groups" field, enter your classmate's email
# MAGIC 3. Role: **Viewer** (not Editor)
# MAGIC 4. Click **Share**
# MAGIC
# MAGIC **Verify the permissions boundary:**
# MAGIC - Ask your classmate to open the dashboard
# MAGIC - They should be able to see the data ✓
# MAGIC - They should be able to interact with filters ✓
# MAGIC - They should NOT be able to click "Edit" on any dataset or widget
# MAGIC - They should NOT see the "Add widget" button
# MAGIC
# MAGIC > **Viewer vs Editor:** Editors can change queries, rename datasets, and rearrange widgets.
# MAGIC > Never grant Editor access to end users — one accidental change can break the dashboard for everyone.

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC # TODOs 20–22 · Genie Space
# MAGIC *Source: Genie Space UI*

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 20 — Add a Custom Instruction for "High-Risk AR"
# MAGIC
# MAGIC **The problem:** If a user asks Genie *"show me high-risk AR records"*, Genie doesn't know
# MAGIC what "high-risk" means without guidance. Without an instruction, it might guess — and guess wrong.
# MAGIC
# MAGIC **Steps:**
# MAGIC 1. Open your Genie space → click **Settings** (gear icon, top right)
# MAGIC 2. Click **SQL instructions** tab
# MAGIC 3. Click **+ Add instruction**
# MAGIC 4. Paste this text exactly:
# MAGIC
# MAGIC > *"'High-risk AR' means records where balance_amount > 10000 AND aging_bucket = '120+' AND recovery_score < 0.20. When a user asks about high-risk accounts, apply all three filters."*
# MAGIC
# MAGIC 5. Click **Save**
# MAGIC
# MAGIC **Test it:** Ask Genie *"How many high-risk AR accounts do we have by state?"*
# MAGIC Click "Show SQL" — confirm all three conditions appear in the WHERE clause.

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 21 — Ask Genie About Provider Write-Off Rate
# MAGIC
# MAGIC **Prompt to type in the Genie Space chat:**
# MAGIC > *"Which providers have the highest write-off rate in the last 6 months?"*
# MAGIC
# MAGIC **What Genie should do:**
# MAGIC - Join `silver_claims` and `silver_denials`
# MAGIC - Filter to claims in the last 6 months (relative to today)
# MAGIC - Calculate write-off rate as: denied claims not appealed ÷ total claims
# MAGIC - Rank providers from highest to lowest write-off rate
# MAGIC
# MAGIC **Reference SQL to compare against:**

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Compare this to what Genie generated
# MAGIC SELECT
# MAGIC   c.provider_id,
# MAGIC   p.provider_name,
# MAGIC   p.specialty,
# MAGIC   COUNT(c.claim_id)                                                       AS total_claims,
# MAGIC   COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END)                  AS denied_claims,
# MAGIC   COUNT(CASE WHEN c.claim_status = 'DENIED' AND d.is_appealed = FALSE
# MAGIC              THEN 1 END)                                                  AS written_off_claims,
# MAGIC   ROUND(
# MAGIC     COUNT(CASE WHEN c.claim_status = 'DENIED' AND d.is_appealed = FALSE THEN 1 END)
# MAGIC     * 100.0 / NULLIF(COUNT(c.claim_id), 0),
# MAGIC     2
# MAGIC   )                                                                       AS write_off_rate_pct
# MAGIC FROM silver_claims c
# MAGIC JOIN bronze_providers p  ON c.provider_id  = p.provider_id
# MAGIC LEFT JOIN silver_denials d ON c.claim_id = d.claim_id
# MAGIC WHERE c.service_month >= ADD_MONTHS(CURRENT_DATE(), -6)
# MAGIC GROUP BY c.provider_id, p.provider_name, p.specialty
# MAGIC HAVING COUNT(c.claim_id) >= 10
# MAGIC ORDER BY write_off_rate_pct DESC
# MAGIC LIMIT 20;

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 22 — Add the Dashboard as a Trusted Asset
# MAGIC
# MAGIC **Why:** When Genie answers a question about KPIs, it can surface the relevant dashboard
# MAGIC as a link in the answer — so users don't have to navigate to it separately.
# MAGIC
# MAGIC **Steps:**
# MAGIC 1. Open your Genie space → **Settings**
# MAGIC 2. Click the **Trusted assets** tab
# MAGIC 3. Click **+ Add asset**
# MAGIC 4. Select **Dashboard**
# MAGIC 5. Search for and select: *"Finance Operations KPI Dashboard"*
# MAGIC 6. Click **Save**
# MAGIC
# MAGIC **Test it:** Ask Genie *"Show me the denial rate trend for 2024"*
# MAGIC — it should answer with data AND show a link to the KPI Dashboard.

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC # TODOs 23–24 · Workflows
# MAGIC *Source: `05_workflow_demo.py`*

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 23 — Add a Dashboard Refresh Task to the Workflow
# MAGIC
# MAGIC **Goal:** After the gold tables are updated, trigger a dashboard dataset refresh automatically.
# MAGIC
# MAGIC **Steps in the Workflow UI:**
# MAGIC 1. Open your `finance_month_end_pipeline` job → click **Tasks**
# MAGIC 2. Click **+ Add task**
# MAGIC 3. Configure:
# MAGIC    - Task name: `dashboard_refresh`
# MAGIC    - Type: **Notebook**
# MAGIC    - Source: **Workspace** → select `04_dashboard_setup.sql`
# MAGIC    - Cluster: same SQL Warehouse as other SQL tasks
# MAGIC    - **Depends on:** `gold_refresh` (Task 3)
# MAGIC 4. Click **Save task**
# MAGIC
# MAGIC **The resulting task graph should be:**
# MAGIC ```
# MAGIC bronze_refresh → silver_transform → gold_refresh → dashboard_refresh
# MAGIC ```
# MAGIC
# MAGIC **Verify:** In the task graph view, `dashboard_refresh` should appear to the right of
# MAGIC `gold_refresh` with an arrow connecting them.

# COMMAND ----------

# MAGIC %md
# MAGIC ## TODO 24 — Set a Timeout on the Bronze Refresh Task
# MAGIC
# MAGIC **Goal:** If `bronze_refresh` (Task 1) hangs — e.g., data source is unavailable — it should
# MAGIC fail after 5 minutes rather than running forever and blocking the rest of the pipeline.
# MAGIC
# MAGIC **Steps in the Workflow UI:**
# MAGIC 1. In your job, click on Task 1 (`bronze_refresh`) to open its settings
# MAGIC 2. Scroll to **Advanced options**
# MAGIC 3. Find **Timeout** → enter `300` seconds (= 5 minutes)
# MAGIC 4. Under **Retries**, set:
# MAGIC    - Max retries: `1`
# MAGIC    - Retry on timeout: `Yes`
# MAGIC 5. Click **Save task**
# MAGIC
# MAGIC **What happens when it times out:**
# MAGIC - The task is marked as FAILED
# MAGIC - Databricks waits the retry delay, then tries once more
# MAGIC - If the retry also times out → downstream tasks are skipped → failure email is sent
# MAGIC
# MAGIC **In-notebook handling (optional — add to `05_workflow_demo.py`):**

# COMMAND ----------

import signal

def timeout_handler(signum, frame):
    raise TimeoutError("Bronze refresh exceeded 5-minute limit")

# Register the handler (Unix only — not available on Windows-based runtimes)
signal.signal(signal.SIGALRM, timeout_handler)
signal.alarm(270)  # warn at 4.5 minutes — gives Databricks time to catch the timeout cleanly

try:
    # ... your bronze load logic here ...
    print("Bronze refresh complete")
finally:
    signal.alarm(0)  # cancel alarm if we finish before the timeout

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC ## All Done
# MAGIC
# MAGIC You've worked through all 24 TODOs. Here's a summary of the key patterns to remember:
# MAGIC
# MAGIC | Pattern | Where used | Why it matters |
# MAGIC |---|---|---|
# MAGIC | `COUNT(CASE WHEN ...)` | TODOs 4, 6, 10 | Conditional count without a subquery |
# MAGIC | `NULLIF(x, 0)` in divisions | TODOs 6, 10, 21 | Prevents divide-by-zero at runtime |
# MAGIC | `RANK() OVER (PARTITION BY ...)` | TODOs 5, 11 | Top-N per group without a self-join |
# MAGIC | `LAG()` | TODOs 10, 11 | Period-over-period change in one pass |
# MAGIC | `AVG() OVER ROWS BETWEEN` | TODO 9 | Rolling average with a sliding window |
# MAGIC | CTE → window → outer filter | TODOs 5, 7, 9, 11 | Window functions can't be in WHERE; push to CTE first |
# MAGIC | `MEASURE()` in metric views | TODOs 13, 14, 15 | Required syntax for metric view measures |
# MAGIC | `QUALIFY` after window | TODO 11 | Filter on a window result without a subquery wrapper |
