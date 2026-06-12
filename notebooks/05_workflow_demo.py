# Databricks notebook source
# MAGIC %md
# MAGIC # Notebook 05: Workflow Orchestration — Month-End Pipeline
# MAGIC **Humana Finance Team — Databricks Workshop**
# MAGIC
# MAGIC This notebook demonstrates how to orchestrate a multi-step data pipeline
# MAGIC using Databricks Workflows. In production, month-end reporting pipelines
# MAGIC run on a schedule — no manual refreshes needed.
# MAGIC
# MAGIC **What we'll build:**
# MAGIC - A 3-task workflow: Bronze → Silver → Gold
# MAGIC - Scheduled for the 1st of each month at 6:00 AM CT
# MAGIC - Email alert on failure
# MAGIC
# MAGIC **This notebook is Task 1 (Bronze Refresh) in the workflow.**

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 1: Notebook Parameters
# MAGIC
# MAGIC Workflows pass parameters to notebooks as widgets.
# MAGIC This lets you run the same notebook with different inputs
# MAGIC (e.g., different months, catalogs, or run modes).

# COMMAND ----------

dbutils.widgets.text("catalog",       "main",              "Catalog")
dbutils.widgets.text("schema",        "finance_training_firstname", "Schema")
dbutils.widgets.text("run_mode",      "incremental",       "Run Mode (full | incremental)")
dbutils.widgets.text("report_month",  "",                  "Report Month (YYYY-MM, blank = last month)")

CATALOG     = dbutils.widgets.get("catalog")
SCHEMA      = dbutils.widgets.get("schema")
RUN_MODE    = dbutils.widgets.get("run_mode")
RPT_MONTH   = dbutils.widgets.get("report_month")

# If no report month specified, default to last month
if not RPT_MONTH:
    from datetime import date
    today = date.today()
    # First day of current month minus 1 day = last day of previous month
    first_this_month = date(today.year, today.month, 1)
    import datetime
    last_month = first_this_month - datetime.timedelta(days=1)
    RPT_MONTH = f"{last_month.year}-{last_month.month:02d}"

print(f"Catalog      : {CATALOG}")
print(f"Schema       : {SCHEMA}")
print(f"Run mode     : {RUN_MODE}")
print(f"Report month : {RPT_MONTH}")

# COMMAND ----------

# MAGIC %md ## Step 2: Validate Source Tables

# COMMAND ----------

import sys

required_tables = [
    f"{CATALOG}.{SCHEMA}.bronze_claims",
    f"{CATALOG}.{SCHEMA}.bronze_members",
    f"{CATALOG}.{SCHEMA}.bronze_providers",
]

print("Validating source tables...")
for t in required_tables:
    try:
        count = spark.table(t).count()
        print(f"  ✓ {t}: {count:,} rows")
    except Exception as e:
        print(f"  ✗ {t}: MISSING — {e}")
        sys.exit(1)

print("\nAll source tables validated.")

# COMMAND ----------

# MAGIC %md ## Step 3: Bronze Refresh — Simulate New Claims Arriving

# COMMAND ----------

# In a real pipeline, this would COPY INTO from a landing zone (S3/ADLS).
# Here we simulate new claims arriving for the report month.

from pyspark.sql import Row
from datetime import date, timedelta
import random

random.seed(99)

report_year  = int(RPT_MONTH[:4])
report_month = int(RPT_MONTH[5:7])

# Generate 500 new claims for the report month
new_claims = []
for i in range(1, 501):
    svc_day = random.randint(1, 28)
    svc_date = date(report_year, report_month, svc_day)
    billed = round(random.uniform(50, 5000), 2)
    status = random.choices(["PAID","DENIED","PENDING"], weights=[65,25,10])[0]
    paid   = round(billed * random.uniform(0.7, 0.95), 2) if status == "PAID" else 0.0

    new_claims.append(Row(
        claim_id         = f"CLM-NEW-{report_year}{report_month:02d}-{i:04d}",
        member_id        = f"MBR-{random.randint(1,5000):06d}",
        provider_id      = f"PRV-{random.randint(1,500):06d}",
        claim_type       = random.choice(["Professional","Inpatient","Outpatient"]),
        service_date     = str(svc_date),
        submit_date      = str(svc_date + timedelta(days=random.randint(1,30))),
        billed_amount    = billed,
        allowed_amount   = round(billed * random.uniform(0.55, 0.95), 2),
        paid_amount      = paid,
        member_liability = round((billed - paid) * 0.10, 2) if paid > 0 else 0.0,
        claim_status     = status,
        denial_category  = random.choice(["prior_auth","medical_necessity","coding_error"]) if status == "DENIED" else None,
        lob              = random.choices(["MA","MCD","COM"], weights=[70,20,10])[0],
        state            = random.choice(["FL","TX","KY","OH","GA"]),
        load_timestamp   = None,
    ))

df_new = spark.createDataFrame(new_claims)
df_new.write.format("delta").mode("append").saveAsTable(f"{CATALOG}.{SCHEMA}.bronze_claims")

new_count = df_new.count()
print(f"✓ Appended {new_count:,} new claims for {RPT_MONTH}")

# COMMAND ----------

# MAGIC %md ## Step 4: Refresh Silver Claims

# COMMAND ----------

# Rebuild silver from bronze (in production this would be incremental/merge)
spark.sql(f"""
  CREATE OR REPLACE TABLE {CATALOG}.{SCHEMA}.silver_claims AS
  SELECT
    c.*,
    p.provider_tier,
    p.specialty,
    p.is_network,
    CAST(c.service_date AS DATE)  AS service_date_dt,
    CAST(c.submit_date  AS DATE)  AS submit_date_dt,
    DATE_TRUNC('month', CAST(c.service_date AS DATE)) AS service_month,
    DATEDIFF(CAST(c.submit_date AS DATE), CAST(c.service_date AS DATE)) AS days_to_submit,
    CURRENT_TIMESTAMP() AS silver_load_ts
  FROM {CATALOG}.{SCHEMA}.bronze_claims c
  LEFT JOIN {CATALOG}.{SCHEMA}.bronze_providers p ON c.provider_id = p.provider_id
  WHERE c.claim_id IS NOT NULL
    AND c.billed_amount > 0
""")

silver_count = spark.table(f"{CATALOG}.{SCHEMA}.silver_claims").count()
print(f"✓ silver_claims refreshed: {silver_count:,} rows")

# COMMAND ----------

# MAGIC %md ## Step 5: Refresh Gold KPI Summary

# COMMAND ----------

# Add a summary row for the report month to gold_kpi_daily
# (Real pipeline would recalculate from silver data)
spark.sql(f"""
  MERGE INTO {CATALOG}.{SCHEMA}.gold_kpi_daily AS target
  USING (
    SELECT
      CAST('{RPT_MONTH}-01' AS DATE) AS kpi_date,
      {report_year}                  AS year,
      {report_month}                 AS month,
      ROUND(
        COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 1.0 / COUNT(*), 4
      )                              AS denial_rate,
      ROUND(
        SUM(paid_amount) / NULLIF(SUM(billed_amount), 0), 4
      )                              AS collection_rate,
      40.0                           AS avg_days_in_ar,
      COUNT(*)                       AS claims_received,
      COUNT(CASE WHEN claim_status = 'PAID' THEN 1 END)    AS claims_paid,
      COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)  AS claims_denied
    FROM {CATALOG}.{SCHEMA}.silver_claims
    WHERE service_month = '{RPT_MONTH}-01'
  ) AS source
  ON target.kpi_date = source.kpi_date
  WHEN MATCHED THEN UPDATE SET *
  WHEN NOT MATCHED THEN INSERT *
""")

print(f"✓ gold_kpi_daily updated for {RPT_MONTH}")

# COMMAND ----------

# MAGIC %md ## Step 6: Data Quality Checks

# COMMAND ----------

checks_passed = True

# Check 1: No duplicate claim_ids in silver
dup_count = spark.sql(f"""
  SELECT COUNT(*) AS cnt FROM (
    SELECT claim_id, COUNT(*) AS n
    FROM {CATALOG}.{SCHEMA}.silver_claims
    GROUP BY claim_id HAVING n > 1
  )
""").collect()[0]["cnt"]

if dup_count > 0:
    print(f"  ✗ DQ FAIL: {dup_count} duplicate claim_ids in silver_claims")
    checks_passed = False
else:
    print(f"  ✓ DQ PASS: No duplicate claim_ids")

# Check 2: Denial rate is within expected range (2%–20%)
denial_rate = spark.sql(f"""
  SELECT ROUND(
    COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 100.0 / COUNT(*), 2
  ) AS dr
  FROM {CATALOG}.{SCHEMA}.silver_claims
  WHERE service_month = '{RPT_MONTH}-01'
""").collect()[0]["dr"]

if denial_rate is not None and (denial_rate < 2 or denial_rate > 20):
    print(f"  ✗ DQ WARN: Denial rate {denial_rate}% is outside expected range [2%, 20%]")
else:
    print(f"  ✓ DQ PASS: Denial rate {denial_rate}% is within expected range")

# Check 3: No NULL billed_amounts
null_billed = spark.sql(f"""
  SELECT COUNT(*) AS cnt FROM {CATALOG}.{SCHEMA}.silver_claims
  WHERE billed_amount IS NULL OR billed_amount <= 0
""").collect()[0]["cnt"]

if null_billed > 0:
    print(f"  ✗ DQ FAIL: {null_billed} rows with NULL or zero billed_amount")
    checks_passed = False
else:
    print(f"  ✓ DQ PASS: All billed_amount values are valid")

if not checks_passed:
    raise Exception("Data quality checks failed — pipeline aborted. Check logs above.")

print("\n✅ All data quality checks passed. Pipeline complete.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 7: Pipeline Run Summary

# COMMAND ----------

summary = spark.sql(f"""
  SELECT
    service_month,
    lob,
    COUNT(*)                                                        AS total_claims,
    COUNT(CASE WHEN claim_status = 'PAID' THEN 1 END)              AS paid_claims,
    COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END)            AS denied_claims,
    ROUND(SUM(billed_amount), 0)                                    AS total_billed,
    ROUND(SUM(paid_amount), 0)                                      AS total_collected,
    ROUND(
      COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) * 100.0
      / COUNT(*), 2
    )                                                               AS denial_rate_pct
  FROM {CATALOG}.{SCHEMA}.silver_claims
  WHERE service_month = '{RPT_MONTH}-01'
  GROUP BY service_month, lob
  ORDER BY lob
""")
display(summary)

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC ## 🗓️ HOW TO CREATE THE WORKFLOW (UI Steps)
# MAGIC
# MAGIC 1. Go to **Workflows** in the left nav → **Create Job**
# MAGIC 2. Name the job: `finance_month_end_pipeline`
# MAGIC
# MAGIC **Add 3 tasks:**
# MAGIC
# MAGIC | Task Name | Notebook | Depends On |
# MAGIC |---|---|---|
# MAGIC | `bronze_refresh` | `00_setup_and_ingestion` | *(none — runs first)* |
# MAGIC | `silver_transform` | `05_workflow_demo` | `bronze_refresh` |
# MAGIC | `gold_refresh` | `04_dashboard_setup` | `silver_transform` |
# MAGIC
# MAGIC **For each task:**
# MAGIC - Type: Notebook
# MAGIC - Cluster: Serverless (or your shared cluster)
# MAGIC - Parameters for `silver_transform`:
# MAGIC   - `catalog` = `main`
# MAGIC   - `schema` = `finance_training_firstname`
# MAGIC   - `run_mode` = `incremental`
# MAGIC
# MAGIC **Schedule:**
# MAGIC - Click "Schedules & Triggers" → Add trigger → Scheduled
# MAGIC - Cron: `0 6 1 * *` (6 AM on the 1st of every month)
# MAGIC - Timezone: America/Chicago (CT)
# MAGIC
# MAGIC **Alerts:**
# MAGIC - Click "Notifications" → Add → enter your email → On Failure
# MAGIC
# MAGIC 3. Click **Run Now** to test it manually
# MAGIC 4. Go to **Runs** tab to see the execution graph and logs
# MAGIC
# MAGIC ---
# MAGIC ## ✅ Workshop Complete!
# MAGIC
# MAGIC You've covered:
# MAGIC - Delta tables (Bronze/Silver/Gold)
# MAGIC - SQL analytics (aggregations, CTEs, window functions)
# MAGIC - Genie Code for query assistance
# MAGIC - Metric views for semantic context
# MAGIC - Dashboards with multiple datasets
# MAGIC - Genie Spaces with NL querying
# MAGIC - Unity Catalog governance
# MAGIC - Automated workflows with scheduling and alerting
# MAGIC
# MAGIC ---
# MAGIC ## 📝 TODOs — Try These Yourself
# MAGIC
# MAGIC **TODO 23:** Add a 4th task to the workflow that runs `04_dashboard_setup.sql`
# MAGIC to refresh dashboard datasets after the gold layer updates.
# MAGIC Where should it go in the dependency chain?
# MAGIC
# MAGIC **TODO 24:** Add a **5-minute timeout** to the `bronze_refresh` task.
# MAGIC In the task settings, look for the "Timeout" field.
# MAGIC What happens if the notebook runs longer than 5 minutes?
# MAGIC How would you handle a timeout in a production pipeline?
