# Humana Finance Team — Databricks Workshop

**Duration:** 2 hours | **Format:** Hands-on  
**Audience:** Finance analysts, AR/billing staff, finance ops

---

## Pre-Workshop Prerequisites

Complete these before attending (budget 30–60 min):

1. **Databricks Free Edition** — sign up at [databricks.com/learn/free-edition](https://databricks.com/learn/free-edition)
   - No credit card required
   - Includes notebooks, SQL editor, dashboards, and AI tools
2. **Databricks Academy account** — [databricks.com/learn/training](https://databricks.com/learn/training)
   - Use the same email as your Free Edition workspace
3. **Optional:** Complete *Databricks Fundamentals* on Academy before attending

---

## Dataset: Revenue Cycle Management (RCM)

Synthetic data generated inline in Notebook 00 — nothing to download or upload.

| Table | Layer | Rows | What it contains |
|---|---|---|---|
| `bronze_claims` | Bronze | ~30K | Raw claim submissions (claim_id, member, provider, billed/allowed/paid, status) |
| `bronze_members` | Bronze | ~5K | Member enrollment: DOB, state, plan type, line of business |
| `bronze_providers` | Bronze | ~500 | Provider network: specialty, tier, NPI |
| `silver_claims` | Silver | ~30K | Cleaned + standardized claims with LOB and provider_tier |
| `silver_denials` | Silver | ~8K | Denial records with CARC codes (prior_auth, medical_necessity, coding_error...) |
| `gold_ar_aging` | Gold | ~10K | AR aging buckets (0-30, 31-60, 61-90, 91-120, 120+) with recovery scores |
| `gold_budget_actuals` | Gold | ~288 | 24 months × 12 departments — budget vs actuals |
| `gold_kpi_daily` | Gold | ~730 | Daily denial rate, collection rate, days-in-AR (2024–2025) |

**Lines of business:** MA (Medicare Advantage) · MCD (Medicaid) · COM (Commercial)

---

## Session Outline

| # | Segment | Format | Time |
|---|---|---|---|
| 1 | Intro & Workspace Tour | Slides | 15 min |
| 2 | Notebooks: Data Setup & Exploration | Hands-on | 20 min |
| 3 | SQL Editor: Finance Analytics | Hands-on | 30 min |
| 4 | Genie Code Demo | Live demo | 15 min |
| 5 | Metric Views for Genie | Hands-on | 20 min |
| 6 | Dashboard Building | Hands-on | 20 min |
| 7 | Genie Space Setup | Demo | 10 min |
| 8 | Governance & Unity Catalog | Demo | 10 min |
| 9 | Workflows: Month-End Automation | Demo | 10 min |

---

## File Guide

```
notebooks/
├── 00_setup_and_ingestion.py   ← Start here. Generates all data, creates Delta tables.
├── 01_sql_basics.sql           ← Open in SQL Editor. Joins, filters, aggregations.
├── 02_advanced_analytics.sql   ← CTEs, window functions, budget variance.
├── 03_metric_views.sql         ← Build the Genie metric view.
├── 04_dashboard_setup.sql      ← Create named datasets for the dashboard.
└── 05_workflow_demo.py         ← Month-end pipeline orchestration.
```

Run notebooks in order: **00 → 01 → 02 → 03 → 04 → 05**

---

## TODO Tracker

There are **24 TODOs** embedded across all notebooks. Work through them during or after the session:

| TODOs | Location | Topic |
|---|---|---|
| 1–3 | `00_setup_and_ingestion.py` | Delta table ops, exploration |
| 4–6 | `01_sql_basics.sql` | Joins, aggregation, filtering |
| 7–9 | `02_advanced_analytics.sql` | CTEs, window functions |
| 10–11 | SQL Editor (Genie Code) | Prompt engineering |
| 12–15 | `03_metric_views.sql` | Metric view YAML syntax |
| 16–19 | Dashboard UI | Chart types, filters, sharing |
| 20–22 | Genie Space UI | Instructions, trusted assets |
| 23–24 | `05_workflow_demo.py` | Job scheduling, alerts |
