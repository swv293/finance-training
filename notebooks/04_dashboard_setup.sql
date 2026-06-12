-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 04 · Dashboard Setup — Finance KPI Dashboard
-- MAGIC **Finance Team · Databricks Workshop**
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## Learning Objectives
-- MAGIC By the end of this notebook you will be able to:
-- MAGIC - Create named SQL datasets that power dashboard widgets
-- MAGIC - Build a multi-widget Finance KPI Dashboard in the Databricks UI
-- MAGIC - Add global date filters that affect all widgets simultaneously
-- MAGIC - Configure cross-filtering and auto-refresh on a dashboard
-- MAGIC - Share a dashboard with your team
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## How Databricks Dashboards Work
-- MAGIC
-- MAGIC ```
-- MAGIC SQL Query (dataset)
-- MAGIC      ↓
-- MAGIC   Dataset  ←── saved, named SQL result
-- MAGIC      ↓
-- MAGIC   Widget   ←── chart, table, counter, or filter connected to a dataset
-- MAGIC      ↓
-- MAGIC Dashboard  ←── canvas of multiple widgets, shareable as a URL
-- MAGIC ```
-- MAGIC
-- MAGIC **Key concept:** Each widget connects to ONE dataset.
-- MAGIC A dataset is just a named SQL query — you write it once and reuse it across widgets.
-- MAGIC
-- MAGIC **Workflow:**
-- MAGIC 1. Write and test queries in the SQL Editor (this notebook)
-- MAGIC 2. Create a new Dashboard
-- MAGIC 3. Add each query as a Dataset
-- MAGIC 4. Add widgets connected to those datasets
-- MAGIC 5. Configure filters and sharing

-- COMMAND ----------

-- 🔧 Set your context
USE CATALOG main;
USE SCHEMA finance_training_firstname;   -- ← change this

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Dataset 1 · Claims Volume & Denial Trend (`ds_claims_trend`)
-- MAGIC
-- MAGIC **Powers:** Line/combo chart — claims volume and denial rate over time
-- MAGIC **Widget title:** "Monthly Claims Volume & Denial Rate"
-- MAGIC **Chart type:** Line chart — x = `service_month`, y = `total_claims` + `denial_rate_pct`
-- MAGIC **Why this chart:** Shows whether claim volume and denial rates are improving or worsening month by month.

-- COMMAND ----------

-- Run this query, verify results, then copy it into Dashboard → Add Dataset → ds_claims_trend
SELECT
  service_month,
  lob,
  COUNT(*)                                                     AS total_claims,
  COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)         AS denied_claims,
  COUNT(CASE WHEN claim_status = 'PAID'   THEN 1 END)         AS paid_claims,
  ROUND(SUM(billed_amount), 0)                                 AS total_billed,
  ROUND(SUM(paid_amount), 0)                                   AS total_collected,
  ROUND(
    COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 100.0
    / COUNT(*),
    2
  )                                                            AS denial_rate_pct,
  ROUND(
    SUM(paid_amount) * 100.0
    / NULLIF(SUM(billed_amount), 0),
    2
  )                                                            AS collection_rate_pct
FROM silver_claims
WHERE service_month >= '2024-01-01'
GROUP BY service_month, lob
ORDER BY service_month, lob;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Dataset 2 · AR Aging Distribution (`ds_ar_aging`)
-- MAGIC
-- MAGIC **Powers:** Stacked bar chart — AR balance by aging bucket, colored by LOB
-- MAGIC **Widget title:** "AR Aging Distribution by Line of Business"
-- MAGIC **Chart type:** Stacked bar — x = `aging_bucket`, y = `total_balance`, color = `lob`
-- MAGIC **Why this chart:** Quickly shows what proportion of your AR is in danger zones (90+ days).
-- MAGIC
-- MAGIC > **Dashboard tip:** Sort the x-axis using `bucket_sort` — not alphabetically.
-- MAGIC > Select "Custom sort" on the x-axis and use `bucket_sort` as the sort field.

-- COMMAND ----------

SELECT
  aging_bucket,
  lob,
  COUNT(*)                          AS record_count,
  ROUND(SUM(balance_amount), 0)     AS total_balance,
  ROUND(AVG(recovery_score), 4)     AS avg_recovery_score,
  ROUND(AVG(days_outstanding), 1)   AS avg_days_outstanding,
  -- Denominator for % of LOB total (window function — works in datasets too)
  ROUND(
    SUM(balance_amount) * 100.0
    / SUM(SUM(balance_amount)) OVER (PARTITION BY lob),
    2
  )                                 AS pct_of_lob_total,
  -- Sort key: keeps buckets in chronological order (not alphabetical)
  CASE aging_bucket
    WHEN '0-30'   THEN 1
    WHEN '31-60'  THEN 2
    WHEN '61-90'  THEN 3
    WHEN '91-120' THEN 4
    WHEN '120+'   THEN 5
  END                               AS bucket_sort
FROM gold_ar_aging
GROUP BY aging_bucket, lob
ORDER BY bucket_sort, lob;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Dataset 3 · Budget vs Actuals (`ds_budget_variance`)
-- MAGIC
-- MAGIC **Powers:** Combo chart — bar = budget, line = actuals, colored by `budget_status`
-- MAGIC **Widget title:** "Department Budget vs Actuals (2024)"
-- MAGIC **Chart type:** Grouped bar or combo — x = `period`, y1 = `budget`, y2 = `actuals`
-- MAGIC **Add a filter widget:** Department dropdown connected to this dataset
-- MAGIC **Why this chart:** The standard month-end close view for finance leadership.

-- COMMAND ----------

SELECT
  department,
  year,
  period,
  month,
  ROUND(budget_amount, 0)     AS budget,
  ROUND(actual_amount, 0)     AS actuals,
  ROUND(variance_amount, 0)   AS variance,
  variance_pct,
  CASE
    WHEN variance_pct >  5  THEN 'Over Budget'
    WHEN variance_pct < -5  THEN 'Under Budget'
    ELSE                         'On Track'
  END                         AS budget_status
FROM gold_budget_actuals
WHERE year = 2024
ORDER BY department, period;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Dataset 4 · Denial Category Breakdown (`ds_denial_breakdown`)
-- MAGIC
-- MAGIC **Powers:** Horizontal bar chart — denial count and amount by root cause category
-- MAGIC **Widget title:** "Denial Breakdown by Category & CARC Code"
-- MAGIC **Chart type:** Horizontal bar — x = `denial_count`, y = `denial_category`, color = `lob`
-- MAGIC **Why this chart:** Identifies the highest-volume denial categories to prioritize prevention efforts.

-- COMMAND ----------

SELECT
  denial_category,
  carc_code,
  denial_description,
  lob,
  state,
  COUNT(*)                                                    AS denial_count,
  ROUND(SUM(denial_amount), 0)                                AS total_denied_amount,
  ROUND(AVG(denial_amount), 2)                                AS avg_denial_amount,
  COUNT(CASE WHEN is_appealed THEN 1 END)                    AS appealed_count,
  ROUND(
    COUNT(CASE WHEN appeal_outcome = 'approved' THEN 1 END) * 100.0
    / NULLIF(COUNT(CASE WHEN is_appealed THEN 1 END), 0),
    2
  )                                                           AS appeal_win_rate_pct
FROM silver_denials
GROUP BY denial_category, carc_code, denial_description, lob, state
ORDER BY denial_count DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Dataset 5 · KPI Trend with Rolling Averages (`ds_kpi_trend`)
-- MAGIC
-- MAGIC **Powers:** Line chart — daily and rolling-average collection/denial rates
-- MAGIC **Widget title:** "Daily Collection Rate Trend (2024–2025)"
-- MAGIC **Chart type:** Line — x = `kpi_date`, y = `rolling_7d_collection_rate`
-- MAGIC **Add a reference line** at y = 0.90 (90% collection rate target)
-- MAGIC **Why this chart:** Smoothed KPI trend removes daily noise and makes performance drift visible.

-- COMMAND ----------

SELECT
  kpi_date,
  year,
  month,
  denial_rate,
  collection_rate,
  avg_days_in_ar,
  claims_received,
  claims_paid,
  claims_denied,
  -- 7-day rolling averages for smoother trend lines
  ROUND(
    AVG(denial_rate) OVER (
      ORDER BY kpi_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ),
    4
  )                             AS rolling_7d_denial_rate,
  ROUND(
    AVG(collection_rate) OVER (
      ORDER BY kpi_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ),
    4
  )                             AS rolling_7d_collection_rate,
  ROUND(
    AVG(avg_days_in_ar) OVER (
      ORDER BY kpi_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ),
    1
  )                             AS rolling_7d_days_in_ar
FROM gold_kpi_daily
ORDER BY kpi_date;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Build the Dashboard in the UI
-- MAGIC
-- MAGIC ### Step 1: Create the Dashboard
-- MAGIC 1. Left nav → **Dashboards** → **Create Dashboard**
-- MAGIC 2. Name it: `Finance Operations KPI Dashboard`
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ### Step 2: Add Datasets
-- MAGIC Click the **Data** tab (top toolbar) → **Add dataset**
-- MAGIC
-- MAGIC For each dataset below:
-- MAGIC - Click "Add dataset" → choose "From SQL"
-- MAGIC - Paste the query from this notebook
-- MAGIC - Name it exactly as shown
-- MAGIC - Click Save
-- MAGIC
-- MAGIC | Dataset Name | Source Query | What it powers |
-- MAGIC |---|---|---|
-- MAGIC | `ds_claims_trend` | Dataset 1 above | Claims volume line chart |
-- MAGIC | `ds_ar_aging` | Dataset 2 above | AR aging stacked bar |
-- MAGIC | `ds_budget_variance` | Dataset 3 above | Budget vs actuals combo |
-- MAGIC | `ds_denial_breakdown` | Dataset 4 above | Denial category bar |
-- MAGIC | `ds_kpi_trend` | Dataset 5 above | Collection rate trend |
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ### Step 3: Add Widgets
-- MAGIC Click **"+ Add widget"** on the canvas and configure each one:
-- MAGIC
-- MAGIC **Widget 1 — Claims Volume Trend**
-- MAGIC - Type: Line chart
-- MAGIC - Dataset: `ds_claims_trend`
-- MAGIC - X-axis: `service_month`
-- MAGIC - Y-axis: `total_claims` (bar), `denial_rate_pct` (line, right axis)
-- MAGIC - Group by / color: `lob`
-- MAGIC
-- MAGIC **Widget 2 — Denial Rate by Category**
-- MAGIC - Type: Horizontal bar chart
-- MAGIC - Dataset: `ds_denial_breakdown`
-- MAGIC - X-axis: `denial_count`
-- MAGIC - Y-axis: `denial_category`
-- MAGIC - Color: `lob`
-- MAGIC
-- MAGIC **Widget 3 — AR Aging Distribution**
-- MAGIC - Type: Stacked bar chart
-- MAGIC - Dataset: `ds_ar_aging`
-- MAGIC - X-axis: `aging_bucket` (sort by `bucket_sort`)
-- MAGIC - Y-axis: `total_balance`
-- MAGIC - Stack by / color: `lob`
-- MAGIC
-- MAGIC **Widget 4 — Budget vs Actuals**
-- MAGIC - Type: Combo chart (bar + line)
-- MAGIC - Dataset: `ds_budget_variance`
-- MAGIC - X-axis: `period`
-- MAGIC - Bar: `budget`
-- MAGIC - Line: `actuals`
-- MAGIC - Color: `budget_status`
-- MAGIC
-- MAGIC **Widget 5 — Collection Rate Trend** *(see TODO 16)*
-- MAGIC - Type: Line chart
-- MAGIC - Dataset: `ds_kpi_trend`
-- MAGIC - X-axis: `kpi_date`
-- MAGIC - Y-axis: `rolling_7d_collection_rate`
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ### Step 4: Add a Global Date Filter
-- MAGIC 1. Click **+ Add widget** → **Filter**
-- MAGIC 2. Type: **Date Range**
-- MAGIC 3. Parameter names: `start_date` and `end_date`
-- MAGIC 4. Connect to `ds_claims_trend.service_month`
-- MAGIC 5. Drag it to the top of the dashboard
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ### Step 5: Enable Cross-Filtering
-- MAGIC Dashboard settings (gear icon) → **Cross-filtering** → **Enabled**
-- MAGIC
-- MAGIC Now clicking a denial category in Widget 2 will filter all other widgets automatically.
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ### Step 6: Schedule Auto-Refresh
-- MAGIC Dashboard toolbar → **Refresh** → **Schedule** → Every **24 hours** → Save
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ### Step 7: Share the Dashboard
-- MAGIC Top right → **Share** → enter team email → role: **Viewer**
-- MAGIC
-- MAGIC > **Viewer vs Editor:**
-- MAGIC > Viewers can see data and interact with filters but cannot modify queries or layout.
-- MAGIC > Never grant Editor access to end users — they could accidentally break the dashboard.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## 📝 TODOs — Try These Yourself
-- MAGIC
-- MAGIC **TODO 16** — Build Widget 5 (Collection Rate Trend) using `ds_kpi_trend`.
-- MAGIC - Chart type: Line
-- MAGIC - Y-axis: `rolling_7d_collection_rate`
-- MAGIC - Add a **reference line** at y = 0.90 (the 90% target)
-- MAGIC - Add a second reference line at y = 0.88 (the alert threshold)
-- MAGIC - Change the line color to red for values below 0.90
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC **TODO 17** — Enable cross-filtering and test it:
-- MAGIC - Click "prior_auth" in the Denial Category chart (Widget 2)
-- MAGIC - Do Widgets 1, 3, and 5 update to show only prior-auth denial data?
-- MAGIC - Click the same bar again to deselect and reset all widgets
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC **TODO 18** — Set the dashboard to auto-refresh every 24 hours.
-- MAGIC *Where is this setting?* Look for "Refresh" in the dashboard toolbar.
-- MAGIC What time does it refresh? Can you change it to refresh at 7:00 AM?
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC **TODO 19** — Share your dashboard with a classmate as a Viewer.
-- MAGIC - Can they see the data? ✓
-- MAGIC - Can they change the SQL in a dataset? (They shouldn't be able to)
-- MAGIC - Can they interact with the date filter? ✓
