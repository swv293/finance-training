-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 02 · Advanced Analytics — CTEs, Window Functions & Budget Variance
-- MAGIC **Finance Team · Databricks Workshop**
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## Learning Objectives
-- MAGIC By the end of this notebook you will be able to:
-- MAGIC - Write CTEs (Common Table Expressions) to structure complex queries
-- MAGIC - Use window functions (`LAG`, `SUM OVER`, `RANK`, `AVG OVER`) for trend and ranking analysis
-- MAGIC - Calculate month-over-month changes in denial and collection rates
-- MAGIC - Analyze budget vs actuals variance by department
-- MAGIC - Identify at-risk AR using multi-condition filtering
-- MAGIC
-- MAGIC ## Why These Matter for Finance
-- MAGIC
-- MAGIC | SQL Feature | Finance Use Case |
-- MAGIC |-------------|-----------------|
-- MAGIC | CTE | Break complex AR aging calculations into readable steps |
-- MAGIC | `LAG()` | Month-over-month denial rate change |
-- MAGIC | `SUM() OVER` | Running YTD collections |
-- MAGIC | `RANK() OVER` | Rank providers by denial rate within a state |
-- MAGIC | `AVG() OVER` | Rolling 7-day average for KPI smoothing |

-- COMMAND ----------

-- 🔧 Set your context
USE CATALOG main;
USE SCHEMA finance_training_firstname;   -- ← change this

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Section 1 — CTEs (Common Table Expressions)
-- MAGIC
-- MAGIC A CTE is a named, temporary result set defined with `WITH name AS (...)`.
-- MAGIC Think of it as creating a named intermediate table that only exists for the duration of your query.
-- MAGIC
-- MAGIC **Why use CTEs instead of nested subqueries?**
-- MAGIC - They read top-to-bottom, like a recipe
-- MAGIC - You can reference the same CTE multiple times
-- MAGIC - They're easier to debug (test each block independently)
-- MAGIC - Databricks SQL optimizes them the same way as subqueries
-- MAGIC
-- MAGIC **Structure:**
-- MAGIC ```sql
-- MAGIC WITH
-- MAGIC   step_one AS (SELECT ...),     -- first intermediate result
-- MAGIC   step_two AS (SELECT ...       -- can reference step_one
-- MAGIC                FROM step_one ...)
-- MAGIC SELECT * FROM step_two;         -- final query using the CTEs
-- MAGIC ```

-- COMMAND ----------

-- 1a. AR aging summary using a two-step CTE
--
-- Step 1 (ar_summary): aggregate AR by bucket and LOB
-- Step 2 (bucket_totals): get total balance per bucket for percentage calculation
-- Final: join them to calculate each LOB's share of its bucket

WITH ar_summary AS (
  -- Step 1: aggregate AR records by aging bucket and line of business
  SELECT
    aging_bucket,
    lob,
    COUNT(*)                          AS record_count,
    ROUND(SUM(balance_amount), 0)     AS total_balance,
    ROUND(AVG(balance_amount), 2)     AS avg_balance,
    ROUND(AVG(recovery_score), 4)     AS avg_recovery_score,
    ROUND(AVG(days_outstanding), 1)   AS avg_days_out
  FROM gold_ar_aging
  GROUP BY aging_bucket, lob
),
bucket_totals AS (
  -- Step 2: total balance per bucket (across all LOBs) for % calculation
  SELECT
    aging_bucket,
    SUM(total_balance) AS bucket_total
  FROM ar_summary
  GROUP BY aging_bucket
)
-- Final: join and compute LOB share within each bucket
SELECT
  s.aging_bucket,
  s.lob,
  s.record_count,
  s.total_balance,
  s.avg_recovery_score,
  s.avg_days_out,
  ROUND(s.total_balance * 100.0 / bt.bucket_total, 2) AS pct_of_bucket
FROM ar_summary s
JOIN bucket_totals bt ON s.aging_bucket = bt.aging_bucket
ORDER BY
  CASE s.aging_bucket         -- custom sort: buckets in chronological order
    WHEN '0-30'   THEN 1
    WHEN '31-60'  THEN 2
    WHEN '61-90'  THEN 3
    WHEN '91-120' THEN 4
    WHEN '120+'   THEN 5
  END,
  s.lob;

-- 💡 CASE in ORDER BY: you can sort by a derived value, not just column names.
-- This keeps aging buckets in the right order (not alphabetical order).

-- COMMAND ----------

-- 1b. At-risk AR: high balance + low recovery + long aging
--
-- This query surfaces the highest-priority accounts for your AR team.
-- An account is "at risk" when:
--   - It has been outstanding 120+ days  (time pressure — collectibility drops fast)
--   - The recovery score is below 0.20   (< 20% probability of collection)
--   - The balance is material (> $50K at the group level)

WITH at_risk AS (
  SELECT
    ar.ar_id,
    ar.claim_id,
    ar.lob,
    ar.state,
    ar.aging_bucket,
    ar.balance_amount,
    ar.recovery_score,
    ar.days_outstanding,
    p.specialty,
    p.provider_tier,
    -- Flag individual high-value records
    CASE
      WHEN ar.balance_amount > 10000 THEN TRUE
      ELSE FALSE
    END AS is_high_value_individual
  FROM gold_ar_aging ar
  LEFT JOIN bronze_providers p ON ar.provider_id = p.provider_id
  WHERE ar.aging_bucket = '120+'
    AND ar.recovery_score < 0.20
)
SELECT
  state,
  lob,
  specialty,
  COUNT(*)                                AS high_risk_count,
  SUM(CASE WHEN is_high_value_individual THEN 1 ELSE 0 END) AS high_value_count,
  ROUND(SUM(balance_amount), 0)           AS total_at_risk_balance,
  ROUND(AVG(recovery_score), 4)           AS avg_recovery_score,
  ROUND(AVG(days_outstanding), 1)         AS avg_days_outstanding
FROM at_risk
GROUP BY state, lob, specialty
HAVING total_at_risk_balance > 50000     -- only show groups with meaningful exposure
ORDER BY total_at_risk_balance DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 📝 TODO 7
-- MAGIC **In the `at_risk` CTE above, add a flag for records that are BOTH high-value AND at risk.**
-- MAGIC
-- MAGIC A record is "critical" when ALL of these are true:
-- MAGIC - `balance_amount > 10000`
-- MAGIC - `aging_bucket = '120+'`
-- MAGIC - `recovery_score < 0.20`
-- MAGIC
-- MAGIC Add a column called `is_critical` to the final SELECT.
-- MAGIC How many critical records exist per state?

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Section 2 — Window Functions
-- MAGIC
-- MAGIC Window functions compute a value for each row based on a "window" of related rows —
-- MAGIC without collapsing the result the way `GROUP BY` does.
-- MAGIC
-- MAGIC **Syntax:**
-- MAGIC ```sql
-- MAGIC FUNCTION() OVER (
-- MAGIC   PARTITION BY column   -- reset the calculation for each group
-- MAGIC   ORDER BY column       -- defines the order within the window
-- MAGIC   ROWS BETWEEN ...      -- optional: limit how far back/forward to look
-- MAGIC )
-- MAGIC ```
-- MAGIC
-- MAGIC | Function | What it does | Finance use case |
-- MAGIC |----------|--------------|-----------------|
-- MAGIC | `LAG(col, 1)` | Previous row's value | Month-over-month change |
-- MAGIC | `SUM() OVER` | Running total | YTD collections |
-- MAGIC | `RANK() OVER` | Rank within group | Top 3 denied providers per state |
-- MAGIC | `AVG() OVER` | Rolling average | Smoothed 7-day denial rate |
-- MAGIC
-- MAGIC > **Key difference from GROUP BY:**
-- MAGIC > `GROUP BY` returns one row per group. Window functions return one row per *input row*,
-- MAGIC > with an extra column showing the window calculation.

-- COMMAND ----------

-- 2a. Month-over-month denial rate change using LAG()
--
-- LAG(col, 1) OVER (PARTITION BY lob ORDER BY month)
-- = "the value of col for the PREVIOUS month, within the same LOB"
--
-- This is the core pattern for any period-over-period comparison.

WITH monthly_denial AS (
  SELECT
    service_month,
    lob,
    COUNT(*)                                                        AS total_claims,
    COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)            AS denied_claims,
    ROUND(
      COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 100.0
      / COUNT(*),
      4
    )                                                               AS denial_rate
  FROM silver_claims
  WHERE service_month >= '2024-01-01'
  GROUP BY service_month, lob
)
SELECT
  service_month,
  lob,
  total_claims,
  denial_rate,
  LAG(denial_rate) OVER (
    PARTITION BY lob           -- reset for each LOB — MA and MCD tracked separately
    ORDER BY service_month
  )                                                                 AS prev_month_rate,
  ROUND(
    denial_rate
    - LAG(denial_rate) OVER (PARTITION BY lob ORDER BY service_month),
    4
  )                                                                 AS mom_change,
  CASE
    WHEN denial_rate > LAG(denial_rate) OVER (PARTITION BY lob ORDER BY service_month)
    THEN '↑ Worse'
    WHEN denial_rate < LAG(denial_rate) OVER (PARTITION BY lob ORDER BY service_month)
    THEN '↓ Better'
    ELSE '→ Flat'
  END                                                               AS trend
FROM monthly_denial
ORDER BY service_month, lob;

-- COMMAND ----------

-- 2b. Running YTD cash collections by LOB
--
-- SUM() OVER with ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- = "sum everything from the start of the partition up to this row"
-- This resets each year because we PARTITION BY lob AND YEAR().

WITH monthly_collections AS (
  SELECT
    service_month,
    lob,
    ROUND(SUM(paid_amount), 0) AS monthly_collected,
    ROUND(SUM(billed_amount), 0) AS monthly_billed
  FROM silver_claims
  WHERE claim_status = 'PAID'
    AND service_month >= '2024-01-01'
  GROUP BY service_month, lob
)
SELECT
  service_month,
  lob,
  monthly_collected,
  monthly_billed,
  ROUND(
    SUM(monthly_collected) OVER (
      PARTITION BY lob, YEAR(service_month)    -- reset each year
      ORDER BY service_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ),
    0
  )                                            AS ytd_collected,
  ROUND(
    SUM(monthly_billed) OVER (
      PARTITION BY lob, YEAR(service_month)
      ORDER BY service_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ),
    0
  )                                            AS ytd_billed
FROM monthly_collections
ORDER BY service_month, lob;

-- COMMAND ----------

-- 2c. Provider ranking by denial rate within each state
--
-- RANK() OVER (PARTITION BY state ORDER BY denial_rate DESC)
-- = "rank this provider among all providers in the same state, highest denial rate = rank 1"
--
-- QUALIFY is a Databricks-specific clause that filters AFTER window functions are computed.
-- It's like WHERE but for window function results.

WITH provider_denial AS (
  SELECT
    c.state,
    c.provider_id,
    p.provider_name,
    p.specialty,
    p.provider_tier,
    COUNT(*)                                                        AS total_claims,
    COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END)          AS denied_claims,
    ROUND(
      COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END) * 100.0
      / COUNT(*),
      2
    )                                                               AS denial_rate_pct
  FROM silver_claims c
  JOIN bronze_providers p ON c.provider_id = p.provider_id
  GROUP BY c.state, c.provider_id, p.provider_name, p.specialty, p.provider_tier
  HAVING total_claims >= 10     -- minimum volume for a meaningful rate
)
SELECT
  state,
  provider_name,
  specialty,
  provider_tier,
  total_claims,
  denial_rate_pct,
  RANK() OVER (
    PARTITION BY state
    ORDER BY denial_rate_pct DESC
  )                                                                 AS denial_rank_in_state,
  -- Compare to state average for this specialty
  ROUND(
    AVG(denial_rate_pct) OVER (PARTITION BY state, specialty),
    2
  )                                                                 AS state_specialty_avg_denial_rate
FROM provider_denial
QUALIFY denial_rank_in_state <= 3     -- top 3 per state only
ORDER BY state, denial_rank_in_state;

-- COMMAND ----------

-- 2d. 7-day rolling average denial and collection rates from KPI daily
--
-- Rolling averages smooth out day-to-day noise in KPIs.
-- "ROWS BETWEEN 6 PRECEDING AND CURRENT ROW" = this row + 6 before it = 7-day window.

SELECT
  kpi_date,
  denial_rate                                                       AS daily_denial_rate,
  collection_rate                                                   AS daily_collection_rate,
  ROUND(
    AVG(denial_rate) OVER (
      ORDER BY kpi_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ),
    4
  )                                                                 AS rolling_7d_denial_rate,
  ROUND(
    AVG(collection_rate) OVER (
      ORDER BY kpi_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ),
    4
  )                                                                 AS rolling_7d_collection_rate,
  avg_days_in_ar
FROM gold_kpi_daily
ORDER BY kpi_date;

-- 💡 Plot rolling_7d_denial_rate as a line chart — the smoothing removes
-- weekend spikes and makes the actual trend visible.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 📝 TODO 8
-- MAGIC **In query 2c, add a column showing how much HIGHER or LOWER each provider's
-- MAGIC denial rate is compared to the state+specialty average.**
-- MAGIC
-- MAGIC Call it `variance_from_state_avg`.
-- MAGIC A positive number means this provider denies more than average (a risk flag).
-- MAGIC A negative number means they deny less (a positive indicator).
-- MAGIC
-- MAGIC *Hint:* `denial_rate_pct - AVG(denial_rate_pct) OVER (PARTITION BY state, specialty)`

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 📝 TODO 9
-- MAGIC **Write a new query that calculates the monthly average of the 7-day rolling collection rate.**
-- MAGIC
-- MAGIC Use `gold_kpi_daily`. Show only months where the **average rolling collection rate
-- MAGIC dropped below 88%** (a performance threshold breach).
-- MAGIC
-- MAGIC Expected columns: `month`, `avg_rolling_collection_rate`, `min_daily_rate`, `max_daily_rate`
-- MAGIC
-- MAGIC *Hint:*
-- MAGIC ```sql
-- MAGIC WITH rolling AS (
-- MAGIC   SELECT kpi_date,
-- MAGIC     AVG(collection_rate) OVER (...) AS rolling_7d
-- MAGIC   FROM gold_kpi_daily
-- MAGIC ),
-- MAGIC monthly AS (...)
-- MAGIC SELECT * FROM monthly WHERE avg_rolling < 0.88;
-- MAGIC ```

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Section 3 — Budget vs Actuals Variance Analysis
-- MAGIC
-- MAGIC **Business question:** Are departments spending within budget?
-- MAGIC
-- MAGIC Budget variance analysis is standard month-end close reporting.
-- MAGIC The sign convention:
-- MAGIC - **Positive variance** = actuals > budget = **overspend** (flag for review)
-- MAGIC - **Negative variance** = actuals < budget = **underspend** (may indicate delayed spend)
-- MAGIC - **Target:** within ±5% of budget is generally "on track"

-- COMMAND ----------

-- 3a. Monthly budget variance by department — status-flagged
SELECT
  period,
  year,
  month,
  department,
  ROUND(budget_amount, 0)    AS budget,
  ROUND(actual_amount, 0)    AS actuals,
  ROUND(variance_amount, 0)  AS variance,
  variance_pct,
  CASE
    WHEN variance_pct >  5  THEN '⚠ Over Budget'
    WHEN variance_pct < -5  THEN '✓ Under Budget'
    ELSE                         '→ On Track'
  END AS budget_status
FROM gold_budget_actuals
ORDER BY year, month, ABS(variance_pct) DESC;

-- COMMAND ----------

-- 3b. YTD budget summary for 2024 — executive summary view
SELECT
  department,
  ROUND(SUM(budget_amount), 0)    AS ytd_budget,
  ROUND(SUM(actual_amount), 0)    AS ytd_actuals,
  ROUND(SUM(variance_amount), 0)  AS ytd_variance,
  ROUND(
    SUM(variance_amount) * 100.0
    / NULLIF(SUM(budget_amount), 0),
    2
  )                                AS ytd_variance_pct
FROM gold_budget_actuals
WHERE year = 2024
GROUP BY department
ORDER BY ABS(ytd_variance_pct) DESC;

-- COMMAND ----------

-- 3c. Departments consistently over budget (3+ months in 2024)
--     Use a CTE to count over-budget months, then filter for chronic offenders.
WITH monthly_status AS (
  SELECT
    department,
    period,
    variance_pct,
    CASE WHEN variance_pct > 5 THEN 1 ELSE 0 END AS is_over_budget
  FROM gold_budget_actuals
  WHERE year = 2024
)
SELECT
  department,
  COUNT(*)                        AS months_tracked,
  SUM(is_over_budget)             AS months_over_budget,
  ROUND(AVG(variance_pct), 2)     AS avg_variance_pct,
  ROUND(MAX(variance_pct), 2)     AS worst_month_variance_pct
FROM monthly_status
GROUP BY department
HAVING months_over_budget >= 3
ORDER BY months_over_budget DESC, avg_variance_pct DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## ✅ Section 2 Complete — What You've Learned
-- MAGIC
-- MAGIC | Concept | Query | Key syntax |
-- MAGIC |---------|-------|------------|
-- MAGIC | Multi-step CTEs | 1a | `WITH a AS (...), b AS (...) SELECT FROM b` |
-- MAGIC | Conditional filtering | 1b | `WHERE bucket = '120+' AND recovery < 0.20` |
-- MAGIC | MoM trend | 2a | `LAG() OVER (PARTITION BY lob ORDER BY month)` |
-- MAGIC | Running total | 2b | `SUM() OVER (ROWS BETWEEN UNBOUNDED PRECEDING...)` |
-- MAGIC | Group ranking | 2c | `RANK() OVER (PARTITION BY state ORDER BY ...)` |
-- MAGIC | Rolling average | 2d | `AVG() OVER (ROWS BETWEEN 6 PRECEDING...)` |
-- MAGIC | Budget variance | 3a–c | `CASE WHEN variance_pct > 5 THEN '⚠ Over Budget'` |
-- MAGIC
-- MAGIC **Continue to:** `03_metric_views.sql` to build the Genie semantic layer
