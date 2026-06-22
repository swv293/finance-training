-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 01 · SQL Basics — Finance Analytics
-- MAGIC **Finance Team · Databricks Workshop**
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## Learning Objectives
-- MAGIC By the end of this notebook you will be able to:
-- MAGIC - Write queries in the Databricks SQL Editor against Delta Lake tables
-- MAGIC - Join multiple tables (claims, members, providers)
-- MAGIC - Aggregate data with `GROUP BY`, `COUNT`, `SUM`, `AVG`
-- MAGIC - Calculate denial rates and collection rates
-- MAGIC - Filter and sort results relevant to healthcare finance
-- MAGIC
-- MAGIC ## Setup
-- MAGIC 1. Open the **SQL Editor** from the left navigation bar
-- MAGIC 2. Select your **SQL Warehouse** from the dropdown (top right)
-- MAGIC 3. Run each query by highlighting it and pressing `Ctrl+Shift+Enter` (Mac: `Cmd+Shift+Enter`)
-- MAGIC
-- MAGIC > **Tip:** Use the schema browser on the left to explore your tables.
-- MAGIC > Click any column name to insert it into your query automatically.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 0 — Set Your Catalog & Schema
-- MAGIC
-- MAGIC Replace `firstname` with the name you used in Notebook 00.
-- MAGIC Run this first so every query below uses your personal schema.

-- COMMAND ----------

-- 🔧 CHANGE THIS: replace 'firstname' with your first name
USE CATALOG main;
USE SCHEMA finance_training_firstname;

-- Confirm it worked — you should see your 8 tables listed
SHOW TABLES;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Section 1 — Claim Volume & Status Overview
-- MAGIC
-- MAGIC **Business question:** What came in this period, and what happened to each claim?
-- MAGIC
-- MAGIC Every AR analyst starts here. Understanding the shape of your claim volume —
-- MAGIC how many were paid, denied, or still pending — tells you where to focus your team.
-- MAGIC
-- MAGIC **Key terms:**
-- MAGIC | Status | Meaning |
-- MAGIC |--------|---------|
-- MAGIC | `PAID` | Adjudicated and payment issued |
-- MAGIC | `DENIED` | Rejected — no payment, action required |
-- MAGIC | `PENDING` | Still in adjudication queue |
-- MAGIC
-- MAGIC **Key metrics:**
-- MAGIC - **Denial rate** = denied claims ÷ total claims × 100 ← your primary KPI
-- MAGIC - **Collection rate** = paid amount ÷ billed amount × 100
-- MAGIC - **Industry benchmark:** denial rate < 5–7%, collection rate > 90%

-- COMMAND ----------

-- 1a. How many claims came in by status?
--     Run this first — it gives you the overall picture.
SELECT
  claim_status,
  COUNT(*)                        AS claim_count,
  ROUND(SUM(billed_amount), 2)    AS total_billed,
  ROUND(SUM(paid_amount), 2)      AS total_paid,
  ROUND(AVG(billed_amount), 2)    AS avg_billed_per_claim
FROM silver_claims
GROUP BY claim_status
ORDER BY claim_count DESC;

-- COMMAND ----------

-- 1b. What is our overall denial rate?
--
-- The CASE WHEN inside COUNT() is a common SQL pattern:
-- it counts only the rows where the condition is true.
-- Dividing by COUNT(*) (all rows) gives you the rate.
SELECT
  COUNT(*)                                                        AS total_claims,
  COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)            AS denied_claims,
  COUNT(CASE WHEN claim_status = 'PAID'   THEN 1 END)            AS paid_claims,
  COUNT(CASE WHEN claim_status = 'PENDING' THEN 1 END)           AS pending_claims,
  ROUND(
    COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 100.0
    / COUNT(*),
    2
  )                                                               AS denial_rate_pct,
  ROUND(
    SUM(paid_amount) * 100.0
    / NULLIF(SUM(billed_amount), 0),
    2
  )                                                               AS collection_rate_pct
FROM silver_claims;

-- ℹ️ Why NULLIF(SUM(billed_amount), 0)?
-- If billed_amount somehow totals to 0, dividing by zero would throw an error.
-- NULLIF returns NULL instead of zero, making the division return NULL safely.

-- COMMAND ----------

-- 1c. Monthly claim volume trend — how is volume changing over time?
--
-- This is your time-series view. Look for:
--   • Spikes in January (AEP enrollment surge)
--   • Rising denial rates over time (process problem)
--   • Seasonality in claim types
SELECT
  service_month,
  COUNT(*)                                                        AS claims_submitted,
  COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)            AS claims_denied,
  ROUND(SUM(billed_amount), 0)                                    AS total_billed,
  ROUND(SUM(paid_amount), 0)                                      AS total_collected,
  ROUND(
    COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 100.0
    / COUNT(*),
    2
  )                                                               AS denial_rate_pct
FROM silver_claims
GROUP BY service_month
ORDER BY service_month;

-- 💡 After running: click the "+" chart icon to plot denial_rate_pct over time.
-- This is how you build a quick ad-hoc trend line without leaving the SQL Editor.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 📝 TODO 4
-- MAGIC **Find the average days-to-payment for PAID claims, broken down by claim type.**
-- MAGIC
-- MAGIC The `silver_claims` table has `service_date_dt` and `submit_date_dt` columns (already cast to DATE).
-- MAGIC `DATEDIFF(end_date, start_date)` returns the number of days between two dates.
-- MAGIC
-- MAGIC Expected output columns: `claim_type`, `avg_days_to_submit`, `claim_count`
-- MAGIC
-- MAGIC ```sql
-- MAGIC -- YOUR CODE HERE
-- MAGIC SELECT
-- MAGIC   claim_type,
-- MAGIC   ...
-- MAGIC FROM silver_claims
-- MAGIC WHERE ...
-- MAGIC GROUP BY ...
-- MAGIC ORDER BY avg_days_to_submit DESC;
-- MAGIC ```

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Section 2 — Provider Analysis
-- MAGIC
-- MAGIC **Business question:** Which providers are driving volume, cost, and denials?
-- MAGIC
-- MAGIC Provider analysis is essential for:
-- MAGIC - **Contract renegotiation** — identify high-cost, high-denial providers
-- MAGIC - **Network management** — flag out-of-network outliers
-- MAGIC - **Billing education** — providers with high coding errors need training
-- MAGIC
-- MAGIC We JOIN `silver_claims` to `bronze_providers` on `provider_id` to get
-- MAGIC specialty, tier, and network status for each claim.

-- COMMAND ----------

-- 2a. Top 10 providers by total billed amount
--
-- A high billed amount is not automatically a problem —
-- but a high billed amount WITH a high denial rate is a red flag.
SELECT
  c.provider_id,
  p.provider_name,
  p.specialty,
  p.provider_tier,
  p.is_network,
  COUNT(c.claim_id)                                               AS claim_count,
  ROUND(SUM(c.billed_amount), 0)                                  AS total_billed,
  ROUND(SUM(c.paid_amount), 0)                                    AS total_paid,
  ROUND(AVG(c.billed_amount), 2)                                  AS avg_billed_per_claim,
  ROUND(
    COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END) * 100.0
    / COUNT(c.claim_id),
    2
  )                                                               AS denial_rate_pct
FROM silver_claims c
JOIN bronze_providers p ON c.provider_id = p.provider_id
GROUP BY c.provider_id, p.provider_name, p.specialty, p.provider_tier, p.is_network
ORDER BY total_billed DESC
LIMIT 10;

-- COMMAND ----------

-- 2b. Denial rate by provider specialty
--
-- Specialties with structurally high denial rates often have
-- complex prior-auth requirements (e.g., Oncology, Behavioral Health).
-- Specialties with avoidable denials (coding errors) need billing education.
SELECT
  p.specialty,
  COUNT(c.claim_id)                                               AS total_claims,
  COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END)          AS denied_claims,
  ROUND(
    COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END) * 100.0
    / COUNT(c.claim_id),
    2
  )                                                               AS denial_rate_pct,
  ROUND(SUM(c.billed_amount), 0)                                  AS total_billed,
  ROUND(
    SUM(c.paid_amount) * 100.0
    / NULLIF(SUM(c.billed_amount), 0),
    2
  )                                                               AS collection_rate_pct
FROM silver_claims c
JOIN bronze_providers p ON c.provider_id = p.provider_id
GROUP BY p.specialty
ORDER BY denial_rate_pct DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Section 3 — Member & Geographic Analysis
-- MAGIC
-- MAGIC **Business question:** Where are claims coming from, and which lines of business need attention?
-- MAGIC
-- MAGIC Geographic analysis helps you:
-- MAGIC - Identify states with regulatory differences (e.g., Medicaid expansion states)
-- MAGIC - Find network gaps (high out-of-network rates in certain states)
-- MAGIC - Route AR follow-up work by state/region
-- MAGIC
-- MAGIC **Lines of Business (LOB):**
-- MAGIC | Code | Plan Type | Key characteristic |
-- MAGIC |------|-----------|-------------------|
-- MAGIC | MA | Medicare Advantage | CMS-regulated, strict PA requirements |
-- MAGIC | MCD | Managed Medicaid | State-regulated, high denial rates common |
-- MAGIC | COM | Commercial | Employer-sponsored, varied contracts |

-- COMMAND ----------

-- 3a. Claims and denial rate by line of business
SELECT
  lob,
  COUNT(*)                                                        AS total_claims,
  ROUND(SUM(billed_amount), 0)                                    AS total_billed,
  ROUND(SUM(paid_amount), 0)                                      AS total_paid,
  COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)            AS denied_claims,
  ROUND(
    COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 100.0
    / COUNT(*),
    2
  )                                                               AS denial_rate_pct,
  ROUND(
    SUM(paid_amount) * 100.0
    / NULLIF(SUM(billed_amount), 0),
    2
  )                                                               AS collection_rate_pct
FROM silver_claims
GROUP BY lob
ORDER BY total_billed DESC;

-- COMMAND ----------

-- 3b. Financial breakdown by state
--     Member liability = what the patient owes (copay + deductible + coinsurance)
--     Uncollected = billed - paid - member_liability (not yet received from payer)
SELECT
  state,
  COUNT(*)                                                        AS claim_count,
  ROUND(SUM(billed_amount), 0)                                    AS total_billed,
  ROUND(SUM(paid_amount), 0)                                      AS total_paid,
  ROUND(SUM(member_liability), 0)                                 AS total_member_liability,
  ROUND(SUM(billed_amount - paid_amount - member_liability), 0)   AS total_uncollected,
  ROUND(
    SUM(paid_amount) * 100.0
    / NULLIF(SUM(billed_amount), 0),
    2
  )                                                               AS collection_rate_pct
FROM silver_claims
GROUP BY state
ORDER BY total_billed DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 📝 TODO 5
-- MAGIC **Which line of business has the HIGHEST denial rate?**
-- MAGIC
-- MAGIC Query 3a answers this. Now extend it:
-- MAGIC Add a column showing the **top denial category** for each LOB.
-- MAGIC (Which denial type — prior_auth, coding_error, etc. — is most common for each LOB?)
-- MAGIC
-- MAGIC Hint: Use a subquery or CTE that groups by `lob` and `denial_category`,
-- MAGIC then ranks with `RANK() OVER (PARTITION BY lob ORDER BY COUNT(*) DESC)`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 📝 TODO 6
-- MAGIC **Add an out-of-network % column to the state breakdown (query 3b).**
-- MAGIC
-- MAGIC Join `bronze_providers` to get `is_network` for each claim's provider.
-- MAGIC Add a column: `oon_claim_pct` = claims where `is_network = false` ÷ total claims × 100
-- MAGIC
-- MAGIC Out-of-network claims typically have:
-- MAGIC - Higher billed amounts
-- MAGIC - Lower payment rates
-- MAGIC - Higher member liability
-- MAGIC
-- MAGIC Does your result match this expectation?

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Section 4 — Denial Category Analysis
-- MAGIC
-- MAGIC **Business question:** WHY are claims being denied, and what can we do about it?
-- MAGIC
-- MAGIC Understanding denial root causes is the foundation of denial management.
-- MAGIC Each category has a different recommended action:
-- MAGIC
-- MAGIC | Category | CARC Code | Action |
-- MAGIC |----------|-----------|--------|
-- MAGIC | Prior Auth | CO-197 | Obtain auth before service; appeal if auth was in place |
-- MAGIC | Medical Necessity | CO-50 | Appeal with clinical documentation |
-- MAGIC | Coding Error | CO-16 | Correct and resubmit — fastest recovery |
-- MAGIC | Timely Filing | CO-29 | Appeal with proof of timely filing |
-- MAGIC | Duplicate | OA-18 | Investigate; usually a write-off |
-- MAGIC
-- MAGIC **Recovery priority:** Coding errors → Prior Auth → Medical Necessity → Timely Filing

-- COMMAND ----------

-- 4a. Denial summary by category — counts, amounts, and appeal outcomes
SELECT
  d.denial_category,
  d.carc_code,
  d.denial_description,
  COUNT(d.denial_id)                                              AS denial_count,
  ROUND(SUM(d.denial_amount), 0)                                  AS total_denied_amount,
  ROUND(AVG(d.denial_amount), 2)                                  AS avg_denial_amount,
  COUNT(CASE WHEN d.is_appealed THEN 1 END)                      AS appealed_count,
  ROUND(
    COUNT(CASE WHEN d.is_appealed THEN 1 END) * 100.0
    / COUNT(d.denial_id),
    2
  )                                                               AS appeal_rate_pct,
  ROUND(
    COUNT(CASE WHEN d.appeal_outcome = 'approved' THEN 1 END) * 100.0
    / NULLIF(COUNT(CASE WHEN d.is_appealed THEN 1 END), 0),
    2
  )                                                               AS appeal_win_rate_pct
FROM silver_denials d
GROUP BY d.denial_category, d.carc_code, d.denial_description
ORDER BY denial_count DESC;

-- 💡 Look at the appeal_win_rate_pct column:
-- A high win rate on appeals means you're leaving money on the table by NOT appealing more.
-- A low win rate means your time is better spent on prevention (process changes).

-- COMMAND ----------

-- 4b. Denial heatmap — which state + category combinations are worst?
--     This tells your AR team WHERE to focus collection efforts.
SELECT
  state,
  denial_category,
  COUNT(*)                          AS denial_count,
  ROUND(SUM(denial_amount), 0)      AS total_denied_amount,
  ROUND(AVG(denial_amount), 2)      AS avg_denial_amount
FROM silver_denials
GROUP BY state, denial_category
ORDER BY state, denial_count DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Section 5 — Financial Summary
-- MAGIC
-- MAGIC **Business question:** What is our bottom-line revenue performance?
-- MAGIC
-- MAGIC This is the executive view: billed vs collected, and the gap.

-- COMMAND ----------

-- 5a. Monthly revenue performance by LOB
--     This is the view your finance leadership wants to see.
SELECT
  lob,
  service_month,
  COUNT(*)                                                AS total_claims,
  ROUND(SUM(billed_amount), 0)                            AS total_billed,
  ROUND(SUM(paid_amount), 0)                              AS total_collected,
  ROUND(SUM(billed_amount) - SUM(paid_amount), 0)         AS revenue_gap,
  ROUND(
    SUM(paid_amount) * 100.0
    / NULLIF(SUM(billed_amount), 0),
    2
  )                                                       AS collection_rate_pct
FROM silver_claims
WHERE service_month >= '2024-01-01'
GROUP BY lob, service_month
ORDER BY service_month, lob;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## ✅ Section 1 Complete — Next Steps
-- MAGIC
-- MAGIC You've queried your RCM data with:
-- MAGIC - Basic aggregations and conditional counts
-- MAGIC - Multi-table JOINs
-- MAGIC - Rate calculations with NULLIF protection
-- MAGIC
-- MAGIC **Continue to: `03_advanced_analytics.sql` for CTEs and window functions
-- MAGIC
-- MAGIC ---
-- MAGIC ### Summary of SQL Patterns Used
-- MAGIC
-- MAGIC | Pattern | When to use |
-- MAGIC |---------|-------------|
-- MAGIC | `COUNT(CASE WHEN ... THEN 1 END)` | Count rows matching a condition |
-- MAGIC | `ROUND(x / NULLIF(y, 0), 2)` | Safe division with rounding |
-- MAGIC | `JOIN ... ON` | Combine tables on a shared key |
-- MAGIC | `WHERE service_month >= '2024-01-01'` | Filter to a date range |
-- MAGIC | `ORDER BY col DESC LIMIT n` | Get the top N results |
