# Finance Team — Databricks 2-Hour Workshop

> Build a complete Revenue Cycle Management analytics pipeline on Databricks —
> from raw synthetic claims data through Delta Lake tables, window-function SQL,
> AI-assisted query generation, metric views, dashboards, and automated scheduling.
> Every step runs in a real workspace, not a sandbox.

**Duration:** 2 hours | **Format:** Hands-on, instructor-led
**Audience:** Finance analysts, AR/billing staff, finance operations

---

## 1. What You Will Build

By the end of the session you will have:

- A **Delta Lake schema** with 8 RCM tables (Bronze → Silver → Gold) under your own Unity Catalog namespace
- Working **SQL analytics** across denial rate trends, AR aging, budget variance, and provider performance
- Complex **window function queries** for period-over-period analysis and multi-dimensional ranking
- A reusable **metric view** powering Genie NL queries with finance-specific dimensions
- A live **Finance KPI Dashboard** with cross-filtering and auto-refresh
- A **scheduled Workflow** that runs the month-end pipeline on a cron trigger

### What This Does NOT Cover

- Production security hardening (column masking is shown conceptually, not configured)
- Power BI / Tableau integration (SQL endpoints are compatible but not walked through)
- Cost optimization or warehouse sizing for large-scale production workloads
- MLflow or machine learning — this workshop is focused on SQL analytics and BI

---

## 2. Prerequisites

Complete these before attending (budget 30–60 min):

1. **Workspace access confirmed** — you should be able to log into the shared training workspace before the session
2. **Databricks Academy account** (optional) — [databricks.com/learn/training](https://databricks.com/learn/training)
3. **Optional pre-read:** *Databricks Fundamentals* on Academy, or the [What is Delta Lake?](https://docs.databricks.com/delta/index.html) doc page

No local software installation is required. Everything runs in the browser.

---

## 3. Dataset: Revenue Cycle Management (RCM)

Synthetic data is generated **inline in Notebook 00** — nothing to download or upload.
All rows are randomly generated with realistic distributions; no real patient or claim data is used.

| Table | Layer | Rows | What it contains |
|---|---|---|---|
| `bronze_claims` | Bronze | ~30K | Raw claim submissions: claim_id, member, provider, billed/allowed/paid amounts, status |
| `bronze_members` | Bronze | ~5K | Member enrollment: DOB, state, plan type, line of business |
| `bronze_providers` | Bronze | ~500 | Provider network: specialty, tier, NPI, network status |
| `silver_claims` | Silver | ~30K | Cleaned + standardized claims joined with LOB and provider_tier |
| `silver_denials` | Silver | ~8K | Denial records with CARC codes (CO-197, CO-50, CO-16, CO-29, OA-18) |
| `gold_ar_aging` | Gold | ~10K | AR aging buckets (0-30, 31-60, 61-90, 91-120, 120+) with recovery scores |
| `gold_budget_actuals` | Gold | ~288 | 24 months × 12 departments — budget vs actuals with variance |
| `gold_kpi_daily` | Gold | ~730 | Daily denial rate, collection rate, days-in-AR (2024–2025) |

**Lines of business:** `MA` (Medicare Advantage) · `MCD` (Medicaid) · `COM` (Commercial)

**CARC denial codes used:**
- `CO-197` — prior authorization required
- `CO-50` — medical necessity not established
- `CO-16` — claim lacks information needed for adjudication
- `CO-29` — timely filing exceeded
- `OA-18` — duplicate claim

---

## 4. Session Outline

| # | Segment | File | Format | Time |
|---|---|---|---|---|
| 1 | Workspace tour & Delta Lake concepts | — | Instructor talk | 15 min |
| 2 | Data setup: generate all 8 RCM tables, explore with Delta | `00_setup_and_ingestion.py` | Hands-on notebook | 20 min |
| 3 | SQL basics: joins, aggregation, denial analysis | `01_sql_basics.sql` | Hands-on SQL Editor | 20 min |
| 4 | Genie Code: AI-generated window function SQL | `02_genie_code_examples.sql` | Live demo + practice | 15 min |
| 5 | Advanced analytics: CTEs, rankings, budget variance | `03_advanced_analytics.sql` | Hands-on SQL Editor | 15 min |
| 6 | Metric views: semantic layer for Genie | `04_metric_views.sql` | Hands-on SQL Editor | 20 min |
| 7 | Dashboard building: 5 widgets, filters, sharing | `05_dashboard_setup.sql` | Hands-on UI | 15 min |
| 8 | Governance: Unity Catalog lineage, audit | — | Demo | 10 min |
| 9 | Workflows: month-end pipeline scheduling | `06_workflow_demo.py` | Demo + configure | 10 min |

---

## 5. File Guide

```
notebooks/
├── 00_setup_and_ingestion.py     ← START HERE. Generates all synthetic data, creates Delta tables.
│                                    Run this first — all other notebooks depend on these tables.
├── 01_sql_basics.sql             ← Open in SQL Editor. Claims analysis, denial rates, provider joins.
├── 03_advanced_analytics.sql     ← CTEs, LAG(), RANK()+QUALIFY, rolling averages, budget variance.
├── 02_genie_code_examples.sql   ← Genie Code demo. Pre-built complex window function queries
│                                    with natural-language prompts and annotated SQL output.
├── 04_metric_views.sql           ← Metric view YAML, 10 measures, 12 dimensions, Genie Space setup.
├── 05_dashboard_setup.sql        ← 5 named datasets for Finance KPI Dashboard, UI build guide.
└── 06_workflow_demo.py           ← MERGE INTO, DQ checks, cron scheduling, dbutils.widgets.
```

Run notebooks in order: **00 → 01 → 02 → 03 → 04 → 05 → 06**


---

## 6. First-Run Commands

After opening Notebook 00, set your schema name in the widget at the top:

```python
# Cell 1 — widget prompt
YOUR_NAME = "firstname"   # e.g. "sarah" — lowercase, no spaces
```

The notebook creates: `main.finance_training_firstname.*`

To verify your tables after running Notebook 00:

```sql
-- Run in SQL Editor
SHOW TABLES IN main.finance_training_firstname;
DESCRIBE DETAIL main.finance_training_firstname.silver_claims;
```

To reset and regenerate all data (useful if you want a clean slate):

```sql
DROP SCHEMA IF EXISTS main.finance_training_firstname CASCADE;
-- Then re-run Notebook 00 from the top
```

---

## 7. TODO Tracker

There are **24 TODOs** embedded across all notebooks.
TODOs 1–9 and 12–24 are in-notebook exercises.
TODOs 10–11 are in `02_genie_code_examples.sql` — they ask you to write Genie Code prompts yourself and evaluate the generated SQL.

| TODOs | Location | Topic |
|---|---|---|
| 1–3 | `00_setup_and_ingestion.py` | Delta DESCRIBE HISTORY, time travel, ALTER TABLE |
| 4–6 | `01_sql_basics.sql` | Denial rate by state, provider join, NULLIF safe division |
| 7–9 | `03_advanced_analytics.sql` | LAG() trend, RANK()+QUALIFY, rolling average |
| 10–11 | `02_genie_code_examples.sql` | Genie Code prompt writing + SQL evaluation |
| 12–15 | `04_metric_views.sql` | Metric view YAML, MEASURE() aggregation, add a dimension |
| 16–19 | Dashboard UI | Chart types, reference lines, cross-filtering, sharing |
| 20–22 | Genie Space UI | NL queries, SQL instructions, trusted assets |
| 23–24 | `06_workflow_demo.py` | Cron expression, DQ alert threshold |

---

## 8. SQL Quick Reference

Patterns used across the workshop — useful to bookmark:

```sql
-- Safe division (avoids divide-by-zero)
SUM(paid_amount) / NULLIF(SUM(billed_amount), 0)

-- Conditional count (no subquery needed)
COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)

-- Month-over-month change
LAG(denial_rate_pct, 1) OVER (PARTITION BY lob ORDER BY service_month)

-- Rolling 3-month average
AVG(denial_rate_pct) OVER (
  PARTITION BY lob ORDER BY service_month
  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
)

-- Rank within group, filter to top N without subquery (Databricks-specific)
RANK() OVER (PARTITION BY specialty ORDER BY denial_rate_pct ASC)
QUALIFY rank_col <= 5

-- Cumulative sum (running total)
SUM(expected_collections) OVER (
  PARTITION BY lob ORDER BY bucket_sort
  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)

-- Metric view measure query
SELECT lob, state, MEASURE(denial_rate) FROM mv_rcm_finance
GROUP BY lob, state;
```

---

## 9. Common Gotchas

| Symptom | Likely cause | Fix |
|---|---|---|
| `Table or view not found` | Wrong schema active | Run `USE SCHEMA main.finance_training_firstname;` first |
| `DESCRIBE HISTORY` returns 1 row | Haven't run any ALTER TABLE yet | Complete TODO 2 in Notebook 00 |
| Window function returns NULL for first row | Expected — LAG has no prior row | Wrap in `COALESCE(LAG(...), 0)` if you need a default |
| Metric view test query returns no rows | Forgot to `GROUP BY` a dimension | `SELECT MEASURE(x) FROM mv_... GROUP BY dim` |
| Dashboard widget shows alphabetical bucket order | Bucket sort not configured | Use `bucket_sort` column in custom sort on x-axis |
| Genie Code generates wrong table name | Schema not set in editor | Set `USE SCHEMA` at top of query tab before prompting |
| Workflow task fails on DQ check | Denial rate outside [2%–20%] | Expected in demo mode — see TODO 24 for threshold adjustment |

---

## 10. Instructor Guide

See `instructor_guide.md` for:
- Full per-segment talk track (15 min each)
- Answers to all 24 TODOs with complete SQL solutions
- Common Q&A (Power BI connection, serverless vs classic compute, Genie data security)
- Pre-session setup checklist

---

*Built by Databricks Field Engineering · June 2026.*
*Data is fully synthetic — no real patient, member, or claims data is used.*
