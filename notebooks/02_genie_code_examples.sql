-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 02 · Genie Code — AI-Assisted SQL for Finance Analytics
-- MAGIC **Finance Team · Databricks Workshop**
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## What Is Genie Code?
-- MAGIC
-- MAGIC Genie Code is the AI coding assistant built into the Databricks SQL Editor.
-- MAGIC It lives in the right-hand panel of the editor and generates SQL from plain-English prompts.
-- MAGIC
-- MAGIC **How to open it:**
-- MAGIC 1. Open the SQL Editor
-- MAGIC 2. Look for the Genie icon (sparkle ✦) in the right toolbar, or press `Cmd+I` / `Ctrl+I`
-- MAGIC 3. Type your prompt in the chat panel — Genie Code reads your open query and schema context
-- MAGIC
-- MAGIC **What it's good at:**
-- MAGIC - Complex window functions you don't want to type from scratch
-- MAGIC - Multi-step CTEs with correct join logic
-- MAGIC - Period-over-period calculations (MoM, YoY, rolling averages)
-- MAGIC - Ranking and scoring queries across multiple dimensions
-- MAGIC
-- MAGIC **What you still need to do:**
-- MAGIC - Read the generated SQL before running it
-- MAGIC - Verify the result makes business sense
-- MAGIC - Refine with follow-up prompts if the output is close but not exact
-- MAGIC
-- MAGIC > **Key message:** Genie Code writes the scaffold in 10 seconds.
-- MAGIC > You still own the SQL and the result. It is a co-pilot, not autopilot.
-- MAGIC
-- MAGIC ---
-- MAGIC
-- MAGIC ## How This Notebook Works
-- MAGIC
-- MAGIC Each section shows:
-- MAGIC 1. **The prompt** — what you would type into Genie Code
-- MAGIC 2. **The generated SQL** — what Genie Code produces (validated and annotated)
-- MAGIC 3. **A verification step** — how to confirm the result is correct
-- MAGIC
-- MAGIC These are genuinely complex queries — the kind where starting from scratch would take 20–30 minutes.
-- MAGIC Genie Code produces a working draft in under 30 seconds.

-- COMMAND ----------

-- 🔧 Set your context first
USE CATALOG main;
USE SCHEMA finance_training_firstname;   -- ← change this

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Query 1 — Denial Rate Trend with Rolling Average and Deviation
-- MAGIC
-- MAGIC ### The Prompt
-- MAGIC > *"Show monthly denial rate by line of business for 2024. Include the previous month's rate,
-- MAGIC > the month-over-month change, a 3-month rolling average, and how far the current month
-- MAGIC > deviates from that rolling average. Flag months where the rate is more than 1 percentage
-- MAGIC > point above the rolling average."*
-- MAGIC
-- MAGIC This is a realistic request from a finance director who wants to know:
-- MAGIC - Is denial rate improving or worsening?
-- MAGIC - Is a bad month a blip or part of a trend?
-- MAGIC - Which months need root-cause investigation?
-- MAGIC
-- MAGIC A query like this requires three separate window functions over the same partition —
-- MAGIC the kind of thing where Genie Code saves you the most time.

-- COMMAND ----------

-- ── Genie Code output (annotated) ────────────────────────────────────────────
--
-- This query uses THREE window functions over the same PARTITION BY lob ORDER BY service_month:
--   1. LAG()      → previous month's denial rate
--   2. AVG() OVER → 3-month rolling average (current + 2 prior months)
--   3. Both combined in a CASE → deviation flag
--
-- The outer SELECT is kept clean by pushing all window logic into a CTE.

WITH monthly_denial AS (
  -- Step 1: calculate raw denial rate per LOB per month
  SELECT
    service_month,
    lob,
    COUNT(*)                                                              AS total_claims,
    COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)                  AS denied_claims,
    ROUND(
      COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 100.0
      / NULLIF(COUNT(*), 0),
      4
    )                                                                     AS denial_rate_pct
  FROM silver_claims
  WHERE service_month BETWEEN '2024-01-01' AND '2024-12-01'
  GROUP BY service_month, lob
),
with_windows AS (
  -- Step 2: layer on three window calculations
  SELECT
    service_month,
    lob,
    total_claims,
    denied_claims,
    denial_rate_pct,

    -- Window 1: previous month's denial rate for this LOB
    LAG(denial_rate_pct, 1) OVER (
      PARTITION BY lob
      ORDER BY service_month
    )                                                                     AS prev_month_rate,

    -- Window 2: month-over-month change (positive = getting worse)
    ROUND(
      denial_rate_pct
      - LAG(denial_rate_pct, 1) OVER (PARTITION BY lob ORDER BY service_month),
      4
    )                                                                     AS mom_change_ppts,

    -- Window 3: 3-month rolling average (current month + 2 prior months)
    -- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW = window of 3 rows
    ROUND(
      AVG(denial_rate_pct) OVER (
        PARTITION BY lob
        ORDER BY service_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
      ),
      4
    )                                                                     AS rolling_3m_avg
  FROM monthly_denial
)
-- Step 3: final output with derived columns
SELECT
  service_month,
  lob,
  total_claims,
  denial_rate_pct,
  prev_month_rate,
  mom_change_ppts,

  -- Direction indicator: intuitive for stakeholders
  CASE
    WHEN mom_change_ppts > 0  THEN '↑ Worse'
    WHEN mom_change_ppts < 0  THEN '↓ Better'
    WHEN mom_change_ppts = 0  THEN '→ Flat'
    ELSE                           '— (first month)'
  END                                                                     AS mom_direction,

  rolling_3m_avg,

  -- Deviation: how far is this month from the 3-month trend?
  ROUND(denial_rate_pct - rolling_3m_avg, 4)                             AS deviation_from_rolling_avg,

  -- Alert flag: more than 1 percentage point above rolling average = investigate
  CASE
    WHEN denial_rate_pct - rolling_3m_avg > 1.0 THEN '⚠ Spike — investigate'
    WHEN denial_rate_pct - rolling_3m_avg < -1.0 THEN '✓ Improvement'
    ELSE '→ Within trend'
  END                                                                     AS trend_alert
FROM with_windows
ORDER BY lob, service_month;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Verify the Result
-- MAGIC
-- MAGIC After running the query above, check:
-- MAGIC 1. Does `prev_month_rate` for January show `NULL`? ✓ (no prior month exists)
-- MAGIC 2. Is `rolling_3m_avg` for January equal to `denial_rate_pct`? ✓ (only 1 month in the window)
-- MAGIC 3. Is `rolling_3m_avg` for February the average of Jan and Feb? ✓
-- MAGIC 4. From March onward, `rolling_3m_avg` should always be 3 months
-- MAGIC
-- MAGIC **Follow-up prompt to try in Genie Code:**
-- MAGIC > *"Now show only the months flagged as '⚠ Spike — investigate' across all LOBs,
-- MAGIC > ordered by deviation from rolling average descending."*

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 📝 TODO 10
-- MAGIC **Use Genie Code to write this from scratch:**
-- MAGIC
-- MAGIC *"Monthly collection rate trend for Medicare Advantage (MA) only in 2024.
-- MAGIC Include the previous month, month-over-month change in percentage points,
-- MAGIC and a column showing whether it improved, worsened, or stayed flat."*
-- MAGIC
-- MAGIC After Genie Code generates it:
-- MAGIC 1. Read the SQL — does it filter `lob = 'MA'` correctly?
-- MAGIC 2. Does it use `LAG()` with `PARTITION BY lob`? (It should — even though you only have one LOB, it's correct practice)
-- MAGIC 3. Run it and verify the result makes sense

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Query 2 — Provider Performance Scorecard with Multi-Dimensional Ranking
-- MAGIC
-- MAGIC ### The Prompt
-- MAGIC > *"Create a provider performance scorecard for providers with at least 20 claims.
-- MAGIC > For each provider, rank them within their specialty by:
-- MAGIC > (1) denial rate — lowest is best,
-- MAGIC > (2) collection rate — highest is best,
-- MAGIC > (3) claim volume — highest is best.
-- MAGIC > Then calculate a composite performance score as the average of those three ranks
-- MAGIC > (lower composite = better overall). Show only providers in the top 25% by composite score
-- MAGIC > within their specialty."*
-- MAGIC
-- MAGIC This is a classic provider network management query. It ranks providers on multiple
-- MAGIC dimensions simultaneously and surfaces the top performers — the kind of analysis that
-- MAGIC would feed a tiering decision or a quality bonus program.
-- MAGIC
-- MAGIC Doing this manually requires four separate window functions (three RANKs + a COUNT for
-- MAGIC the specialty total) and a QUALIFY filter on a derived column. Genie Code handles all of it.

-- COMMAND ----------

-- ── Genie Code output (annotated) ────────────────────────────────────────────
--
-- Pattern: multiple RANK() OVER calls in a single CTE, all sharing the same PARTITION BY specialty.
-- Each RANK() uses a different ORDER BY because "best" means something different for each metric.
--
-- QUALIFY filters the final result AFTER window functions are computed —
-- this is a Databricks-specific clause that avoids a wrapping subquery.

WITH provider_metrics AS (
  -- Step 1: aggregate raw metrics per provider
  SELECT
    c.provider_id,
    p.provider_name,
    p.specialty,
    p.provider_tier,
    p.is_network,
    COUNT(c.claim_id)                                                     AS total_claims,
    COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END)                AS denied_claims,
    ROUND(
      COUNT(CASE WHEN c.claim_status = 'DENIED' THEN 1 END) * 100.0
      / NULLIF(COUNT(c.claim_id), 0),
      2
    )                                                                     AS denial_rate_pct,
    ROUND(
      SUM(c.paid_amount) * 100.0
      / NULLIF(SUM(c.billed_amount), 0),
      2
    )                                                                     AS collection_rate_pct
  FROM silver_claims c
  JOIN bronze_providers p ON c.provider_id = p.provider_id
  GROUP BY
    c.provider_id, p.provider_name, p.specialty, p.provider_tier, p.is_network
  HAVING COUNT(c.claim_id) >= 20      -- minimum volume for a meaningful rate
),
with_ranks AS (
  -- Step 2: three independent RANK() calls, all partitioned by specialty
  SELECT
    *,

    -- Rank 1: denial rate — ASCENDING (rank 1 = lowest denial rate = best)
    RANK() OVER (
      PARTITION BY specialty
      ORDER BY denial_rate_pct ASC
    )                                                                     AS denial_rank,

    -- Rank 2: collection rate — DESCENDING (rank 1 = highest collection rate = best)
    RANK() OVER (
      PARTITION BY specialty
      ORDER BY collection_rate_pct DESC
    )                                                                     AS collection_rank,

    -- Rank 3: volume — DESCENDING (rank 1 = highest volume = best)
    RANK() OVER (
      PARTITION BY specialty
      ORDER BY total_claims DESC
    )                                                                     AS volume_rank,

    -- Count of providers in this specialty (for percentile calculation)
    COUNT(*) OVER (PARTITION BY specialty)                                AS specialty_provider_count
  FROM provider_metrics
),
with_composite AS (
  -- Step 3: composite score = average rank across all three dimensions
  -- Lower composite score = better overall performer
  SELECT
    *,
    ROUND(
      (denial_rank + collection_rank + volume_rank) / 3.0,
      2
    )                                                                     AS composite_score,
    -- Percentile position: 0.25 = top 25% (lowest scores)
    ROUND(
      (denial_rank + collection_rank + volume_rank) / 3.0
      / NULLIF(specialty_provider_count, 0),
      4
    )                                                                     AS composite_percentile
  FROM with_ranks
)
SELECT
  specialty,
  provider_name,
  provider_tier,
  is_network,
  total_claims,
  denial_rate_pct,
  collection_rate_pct,
  denial_rank,
  collection_rank,
  volume_rank,
  composite_score,
  specialty_provider_count,
  -- Performance tier based on composite percentile
  CASE
    WHEN composite_percentile <= 0.25 THEN 'Tier 1 — Top Performer'
    WHEN composite_percentile <= 0.50 THEN 'Tier 2 — Above Average'
    WHEN composite_percentile <= 0.75 THEN 'Tier 3 — Below Average'
    ELSE                                   'Tier 4 — Underperformer'
  END                                                                     AS performance_tier
FROM with_composite
-- QUALIFY filters AFTER window functions — keep only top 25% within each specialty
QUALIFY composite_percentile <= 0.25
ORDER BY specialty, composite_score ASC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Verify the Result
-- MAGIC
-- MAGIC After running:
-- MAGIC 1. For each specialty, `denial_rank = 1` should go to the provider with the LOWEST `denial_rate_pct`
-- MAGIC 2. `composite_score` should be the average of the three rank columns — spot-check one row manually
-- MAGIC 3. The `QUALIFY` should keep only providers where `composite_percentile <= 0.25`
-- MAGIC    — verify by checking `composite_score / specialty_provider_count` for any row
-- MAGIC 4. A specialty with only 4 providers should show at most 1 in the result (top 25%)
-- MAGIC
-- MAGIC **Follow-up prompt to try in Genie Code:**
-- MAGIC > *"Add a column showing each provider's denial rate vs the specialty average,
-- MAGIC > formatted as '+X.XX ppts' or '-X.XX ppts'. Show only out-of-network providers
-- MAGIC > who are still top performers (composite_percentile <= 0.25)."*

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 📝 TODO 11
-- MAGIC **Use Genie Code to add a year-over-year comparison to the scorecard.**
-- MAGIC
-- MAGIC Start with the composite scorecard above already in the editor.
-- MAGIC Then type this follow-up prompt in Genie Code:
-- MAGIC
-- MAGIC *"Modify this query to compare 2024 vs 2025 performance.
-- MAGIC For each provider, show their composite score in 2024 and 2025 side by side,
-- MAGIC and add a column showing whether their overall ranking improved or worsened."*
-- MAGIC
-- MAGIC After Genie Code generates the updated query:
-- MAGIC 1. Does it use a PIVOT or a self-join to get 2024 vs 2025 in the same row?
-- MAGIC 2. Does it handle providers who have claims in only one year?
-- MAGIC 3. How does it define "improved" — lower composite score? Higher rank?

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Query 3 — AR Recovery Waterfall with Cumulative Expected Collections
-- MAGIC
-- MAGIC ### The Prompt
-- MAGIC > *"Build an AR recovery waterfall. For each aging bucket, show the total outstanding balance,
-- MAGIC > the average recovery probability, the expected collectible amount, and the expected
-- MAGIC > write-off amount. Then add a cumulative expected collections column that accumulates
-- MAGIC > from the youngest bucket to the oldest, so I can see the running total of what we
-- MAGIC > expect to collect across all aging buckets. Break this down by line of business."*
-- MAGIC
-- MAGIC This is a treasury/collections planning query. The output answers:
-- MAGIC *"Of our total open AR, how much do we realistically expect to collect — and from which buckets?"*
-- MAGIC
-- MAGIC The cumulative SUM() OVER with a custom sort order (youngest bucket → oldest) is the
-- MAGIC tricky part — Genie Code handles the CASE-in-ORDER-BY pattern without being prompted for it.

-- COMMAND ----------

-- ── Genie Code output (annotated) ────────────────────────────────────────────
--
-- Key pattern: SUM() OVER with ORDER BY on a CASE expression.
-- You can't ORDER BY aging_bucket alphabetically (0-30, 120+, 31-60 would be wrong order).
-- Genie Code correctly adds a sort key via CASE to enforce chronological bucket order.

WITH ar_by_bucket AS (
  -- Step 1: aggregate AR balance, recovery score, and derived amounts per bucket + LOB
  SELECT
    aging_bucket,
    lob,
    COUNT(*)                                                              AS record_count,
    ROUND(SUM(balance_amount), 2)                                         AS total_balance,
    ROUND(AVG(recovery_score), 4)                                         AS avg_recovery_score,

    -- Expected collectible = balance × recovery probability
    ROUND(SUM(balance_amount * recovery_score), 2)                        AS expected_collections,

    -- Expected write-off = balance × (1 - recovery probability)
    ROUND(SUM(balance_amount * (1 - recovery_score)), 2)                  AS expected_writeoff,

    -- Sort key for window ordering — alphabetical order of bucket names is wrong
    CASE aging_bucket
      WHEN '0-30'   THEN 1
      WHEN '31-60'  THEN 2
      WHEN '61-90'  THEN 3
      WHEN '91-120' THEN 4
      WHEN '120+'   THEN 5
    END                                                                   AS bucket_sort
  FROM gold_ar_aging
  GROUP BY aging_bucket, lob
),
with_cumulative AS (
  -- Step 2: cumulative expected collections from youngest → oldest bucket, per LOB
  -- SUM() OVER with ORDER BY bucket_sort accumulates across buckets in chronological order
  SELECT
    *,
    ROUND(
      SUM(expected_collections) OVER (
        PARTITION BY lob                       -- reset for each line of business
        ORDER BY bucket_sort                   -- youngest bucket first
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ),
      2
    )                                                                     AS cumulative_expected_collections,

    -- Total balance for this LOB (used to calculate % of total AR)
    SUM(total_balance) OVER (PARTITION BY lob)                            AS lob_total_balance
  FROM ar_by_bucket
)
SELECT
  aging_bucket,
  lob,
  record_count,
  total_balance,
  avg_recovery_score,
  expected_collections,
  expected_writeoff,
  cumulative_expected_collections,

  -- What % of this LOB's total AR do we expect to collect from this bucket and all younger ones?
  ROUND(
    cumulative_expected_collections * 100.0 / NULLIF(lob_total_balance, 0),
    2
  )                                                                       AS cumulative_recovery_pct_of_ar,

  -- Collection efficiency per bucket: what fraction of this bucket's balance is recoverable?
  ROUND(
    expected_collections * 100.0 / NULLIF(total_balance, 0),
    2
  )                                                                       AS bucket_recovery_pct
FROM with_cumulative
ORDER BY lob, bucket_sort;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Verify the Result
-- MAGIC
-- MAGIC After running:
-- MAGIC 1. `expected_collections + expected_writeoff` should equal `total_balance` for every row
-- MAGIC    (check: `balance × recovery + balance × (1 - recovery) = balance`)
-- MAGIC 2. `cumulative_expected_collections` for the last bucket (120+) should equal
-- MAGIC    the total of all `expected_collections` for that LOB
-- MAGIC 3. `bucket_recovery_pct` should decrease as aging bucket gets older
-- MAGIC    (older buckets have lower recovery scores → lower collection %):
-- MAGIC    0-30 should be highest, 120+ should be lowest
-- MAGIC 4. `cumulative_recovery_pct_of_ar` for the 120+ bucket should be less than 100%
-- MAGIC    (because we don't expect to collect 100% of total AR)
-- MAGIC
-- MAGIC **Follow-up prompt to try in Genie Code:**
-- MAGIC > *"Add a column showing how much of the total expected write-off is concentrated
-- MAGIC > in the 120+ bucket as a percentage. If it's above 60%, flag it as 'High write-off concentration'."*

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC ## Summary — When to Use Genie Code
-- MAGIC
-- MAGIC | Query type | Time to write manually | With Genie Code | Best prompt strategy |
-- MAGIC |---|---|---|---|
-- MAGIC | Single window function | 5 min | 30 sec | Describe the partition + order + what you want |
-- MAGIC | Multiple windows on same partition | 20 min | 1 min | Describe each metric and its "best" direction |
-- MAGIC | Multi-step CTE with window | 30 min | 2 min | Describe the business question, not the SQL steps |
-- MAGIC | Cumulative with custom sort order | 25 min | 1 min | Mention the ordering rule explicitly (youngest→oldest) |
-- MAGIC | Follow-up refinement | 10 min | 20 sec | Paste the existing query + describe the addition |
-- MAGIC
-- MAGIC **The pattern that works best:**
-- MAGIC 1. Describe the **business question** in plain English — not the SQL steps
-- MAGIC 2. Mention the **table names** so Genie Code knows where to look
-- MAGIC 3. Specify **ordering direction** for rankings ("lowest denial rate is best")
-- MAGIC 4. Use **follow-up prompts** to refine rather than rewriting the original prompt
-- MAGIC
-- MAGIC **Continue to: `04_metric_views.sql` to build the Genie semantic layer
