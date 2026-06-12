# Databricks notebook source
# MAGIC %md
# MAGIC # Notebook 00: Setup & Data Ingestion
# MAGIC **Finance Team — Databricks Workshop**
# MAGIC
# MAGIC This notebook:
# MAGIC 1. Creates the training catalog and schema
# MAGIC 2. Generates a synthetic Revenue Cycle Management (RCM) dataset
# MAGIC 3. Writes it to Delta tables following the Medallion Architecture
# MAGIC 4. Introduces core Databricks notebook concepts
# MAGIC
# MAGIC **Run time:** ~3–5 minutes
# MAGIC
# MAGIC ---
# MAGIC ### Medallion Architecture
# MAGIC ```
# MAGIC Raw Data (CSV/API)
# MAGIC       ↓
# MAGIC   BRONZE  ← Raw ingestion, minimal transformation, full audit trail
# MAGIC       ↓
# MAGIC   SILVER  ← Cleaned, deduplicated, standardized
# MAGIC       ↓
# MAGIC    GOLD   ← Aggregated, analytics-ready, joined for reporting
# MAGIC ```

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 1: Configure Your Catalog and Schema
# MAGIC
# MAGIC Replace `your_name` below with your first name (lowercase, no spaces).
# MAGIC This keeps everyone's data isolated in the shared workspace.

# COMMAND ----------

# Replace with your first name (lowercase, no spaces, e.g. "sarah" or "james")
YOUR_NAME = "firstname"

CATALOG = "main"                           # Use 'main' on Free Edition
SCHEMA   = f"finance_training_{YOUR_NAME}" # Unique schema per attendee

print(f"Catalog : {CATALOG}")
print(f"Schema  : {SCHEMA}")
print(f"Tables will be created at: {CATALOG}.{SCHEMA}.*")

# COMMAND ----------

# MAGIC %md ## Step 2: Create the Schema

# COMMAND ----------

spark.sql(f"CREATE CATALOG IF NOT EXISTS {CATALOG}")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{SCHEMA}")
spark.sql(f"USE CATALOG {CATALOG}")
spark.sql(f"USE SCHEMA {SCHEMA}")

print(f"✓ Ready to use {CATALOG}.{SCHEMA}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 3: Generate Synthetic RCM Data
# MAGIC
# MAGIC We generate realistic healthcare finance data inline — no file uploads needed.
# MAGIC The data models a health plan managing:
# MAGIC - **Members:** Enrolled individuals across MA, Medicaid, and Commercial plans
# MAGIC - **Claims:** Medical claims submitted by providers for services rendered
# MAGIC - **Providers:** In-network physicians, hospitals, and specialists
# MAGIC - **Denials:** Claims that were denied and the reason why
# MAGIC - **AR Aging:** Outstanding balances organized by how long they've been unpaid
# MAGIC - **KPI Daily:** Daily operational metrics (denial rate, collection rate, days-in-AR)
# MAGIC - **Budget vs Actuals:** Monthly department spend vs budget targets

# COMMAND ----------

import random
import math
from datetime import date, timedelta
from pyspark.sql import Row
from pyspark.sql.types import *

random.seed(42)

def rand_date(start: date, end: date) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))

def rand_choice(lst, weights=None):
    return random.choices(lst, weights=weights, k=1)[0]

# ── Constants ──────────────────────────────────────────────────────────────────
STATES    = ["FL","TX","KY","OH","GA","LA","TN","IN","SC","PR"]
ST_WTS    = [18,  14,  10,  10,  8,   6,   6,   6,   5,   3 ]
LOBS      = ["MA","MCD","COM"]
LOB_WTS   = [70,   20,   10 ]
SPECIALTIES = ["PCP","Cardiology","Orthopedics","Oncology","Behavioral Health",
               "Emergency","SNF","Home Health","Radiology","Physical Therapy"]
CLAIM_TYPES = ["Professional","Inpatient","Outpatient","DME","Pharmacy"]
CT_WTS      = [45, 20, 25, 5, 5]
DENIAL_CATS = ["prior_auth","medical_necessity","coding_error","timely_filing","duplicate"]
DC_WTS      = [22, 18, 16, 12, 8]  # remaining ~24% are clean pays
CARC_MAP    = {
    "prior_auth":        "CO-197",
    "medical_necessity": "CO-50",
    "coding_error":      "CO-16",
    "timely_filing":     "CO-29",
    "duplicate":         "OA-18",
}
TIERS      = ["tier_1","tier_2","tier_3"]
DEPTS      = ["Medical_Mgmt","Claims_Ops","Provider_Relations","Member_Services",
              "IT","Compliance","Finance","HR","Contracting","Analytics","Legal","Marketing"]

# COMMAND ----------

# MAGIC %md ### 3a. Bronze: Members (5,000 rows)

# COMMAND ----------

FIRST_NAMES = ["James","Mary","John","Patricia","Robert","Jennifer","Michael","Linda",
               "William","Barbara","David","Elizabeth","Richard","Susan","Joseph","Jessica",
               "Thomas","Sarah","Charles","Karen","Maria","Carlos","Ana","Luis","Sofia",
               "Wei","Mei","Jin","Yuki","Fatima","Aisha","Omar","Priya","Raj","Sanjay"]
LAST_NAMES  = ["Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis",
               "Rodriguez","Martinez","Hernandez","Lopez","Gonzalez","Wilson","Anderson",
               "Thomas","Taylor","Moore","Jackson","Martin","Lee","Perez","Thompson","White",
               "Harris","Sanchez","Clark","Ramirez","Lewis","Robinson","Walker","Young","Allen"]

members = []
for i in range(1, 5001):
    dob = rand_date(date(1940,1,1), date(2005,12,31))
    enroll_date = rand_date(date(2020,1,1), date(2024,6,1))
    lob = rand_choice(LOBS, LOB_WTS)
    members.append(Row(
        member_id    = f"MBR-{i:06d}",
        first_name   = rand_choice(FIRST_NAMES),
        last_name    = rand_choice(LAST_NAMES),
        date_of_birth= str(dob),
        gender       = rand_choice(["M","F","Other"], [48,48,4]),
        state        = rand_choice(STATES, ST_WTS),
        lob          = lob,
        plan_type    = {"MA":"HMO","MCD":"Managed_Medicaid","COM":"PPO"}[lob],
        enrollment_date = str(enroll_date),
        is_active    = random.random() > 0.05,
    ))

df_members = spark.createDataFrame(members)
df_members.write.format("delta").mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.bronze_members")
print(f"✓ bronze_members: {df_members.count():,} rows")

# COMMAND ----------

# MAGIC %md ### 3b. Bronze: Providers (500 rows)

# COMMAND ----------

PROVIDER_GROUPS = ["Regional Medical Group","Community Health Partners","Integrated Care Network",
                   "Metro Physicians LLC","Premier Health Associates","Valley Medical Center",
                   "Coastal Healthcare","Sunrise Medical Group","Alliance Health","Nexus Care"]

providers = []
for i in range(1, 501):
    specialty = rand_choice(SPECIALTIES)
    tier      = rand_choice(TIERS, [40, 40, 20])
    providers.append(Row(
        provider_id    = f"PRV-{i:06d}",
        npi            = f"{1000000000 + i}",
        provider_name  = f"{rand_choice(LAST_NAMES)}, {rand_choice(FIRST_NAMES)} MD",
        group_name     = rand_choice(PROVIDER_GROUPS),
        specialty      = specialty,
        provider_tier  = tier,
        state          = rand_choice(STATES, ST_WTS),
        is_network     = random.random() > 0.08,
        contract_rate_pct = round(random.uniform(0.70, 1.05), 4),
    ))

df_providers = spark.createDataFrame(providers)
df_providers.write.format("delta").mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.bronze_providers")
print(f"✓ bronze_providers: {df_providers.count():,} rows")

# COMMAND ----------

# MAGIC %md ### 3c. Bronze: Claims (30,000 rows)

# COMMAND ----------

member_ids   = [m.member_id for m in members]
provider_ids = [p.provider_id for p in providers]
member_lob   = {m.member_id: m.lob for m in members}

claims = []
for i in range(1, 30001):
    mid = rand_choice(member_ids)
    pid = rand_choice(provider_ids)
    svc_date    = rand_date(date(2023,1,1), date(2025,6,30))
    submit_date = svc_date + timedelta(days=random.randint(1, 45))
    billed = round(random.uniform(50, 8000), 2)
    allowed = round(billed * random.uniform(0.55, 0.95), 2)

    # Denial logic: ~30% denied
    deny_roll = random.random()
    if deny_roll < 0.30:
        status     = "DENIED"
        paid       = 0.0
        denial_cat = rand_choice(DENIAL_CATS, DC_WTS)
    elif deny_roll < 0.05 + 0.30:
        status     = "PENDING"
        paid       = 0.0
        denial_cat = None
    else:
        status     = "PAID"
        paid       = round(allowed * random.uniform(0.90, 1.00), 2)
        denial_cat = None

    member_liab = round((allowed - paid) * random.uniform(0.05, 0.20), 2) if paid > 0 else 0.0

    claims.append(Row(
        claim_id       = f"CLM-{i:07d}",
        member_id      = mid,
        provider_id    = pid,
        claim_type     = rand_choice(CLAIM_TYPES, CT_WTS),
        service_date   = str(svc_date),
        submit_date    = str(submit_date),
        billed_amount  = billed,
        allowed_amount = allowed,
        paid_amount    = paid,
        member_liability = member_liab,
        claim_status   = status,
        denial_category= denial_cat,
        lob            = member_lob.get(mid, "MA"),
        state          = rand_choice(STATES, ST_WTS),
    ))

df_claims = spark.createDataFrame(claims)
df_claims.write.format("delta").mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.bronze_claims")
print(f"✓ bronze_claims: {df_claims.count():,} rows")

# COMMAND ----------

# MAGIC %md ### 3d. Silver: Claims (cleaned + enriched)

# COMMAND ----------

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
print(f"✓ silver_claims: {spark.table(f'{CATALOG}.{SCHEMA}.silver_claims').count():,} rows")

# COMMAND ----------

# MAGIC %md ### 3e. Silver: Denials (8,000 rows — denial detail with CARC codes)

# COMMAND ----------

DENIAL_DESCS = {
    "prior_auth":        "Precertification/authorization absent",
    "medical_necessity": "Service not deemed medically necessary",
    "coding_error":      "Claim/service lacks information or has billing error",
    "timely_filing":     "Time limit for filing has expired",
    "duplicate":         "Exact duplicate claim/service",
}
ACTIONS = {
    "prior_auth":        "correct_and_resubmit",
    "medical_necessity": "appeal",
    "coding_error":      "correct_and_resubmit",
    "timely_filing":     "appeal",
    "duplicate":         "write_off",
}

denied_claims = [c for c in claims if c.claim_status == "DENIED"]
random.shuffle(denied_claims)
denied_sample = denied_claims[:8000]

denials = []
for i, c in enumerate(denied_sample, 1):
    cat = c.denial_category or rand_choice(DENIAL_CATS, DC_WTS)
    appeal_date = rand_date(
        date.fromisoformat(c.service_date) + timedelta(days=30),
        date.fromisoformat(c.service_date) + timedelta(days=120)
    ) if random.random() > 0.45 else None

    denials.append(Row(
        denial_id       = f"DEN-{i:07d}",
        claim_id        = c.claim_id,
        member_id       = c.member_id,
        provider_id     = c.provider_id,
        denial_date     = c.submit_date,
        denial_category = cat,
        carc_code       = CARC_MAP[cat],
        denial_description = DENIAL_DESCS[cat],
        recommended_action = ACTIONS[cat],
        denial_amount   = c.billed_amount,
        is_appealed     = appeal_date is not None,
        appeal_date     = str(appeal_date) if appeal_date else None,
        appeal_outcome  = rand_choice(["approved","denied","pending"], [35,50,15]) if appeal_date else None,
        lob             = c.lob,
        state           = c.state,
    ))

df_denials = spark.createDataFrame(denials)
df_denials.write.format("delta").mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.silver_denials")
print(f"✓ silver_denials: {df_denials.count():,} rows")

# COMMAND ----------

# MAGIC %md ### 3f. Gold: AR Aging (10,000 rows)

# COMMAND ----------

BUCKETS = ["0-30","31-60","61-90","91-120","120+"]
BKT_WTS = [35,    25,     18,     12,      10   ]
# Recovery probability declines with age
RECOVERY_RANGE = {
    "0-30":   (0.85, 0.99),
    "31-60":  (0.70, 0.89),
    "61-90":  (0.45, 0.74),
    "91-120": (0.25, 0.54),
    "120+":   (0.05, 0.29),
}

ar_rows = []
pending_claims = [c for c in claims if c.claim_status in ("DENIED","PENDING")]
random.shuffle(pending_claims)

for i, c in enumerate(pending_claims[:10000], 1):
    bucket = rand_choice(BUCKETS, BKT_WTS)
    lo, hi = RECOVERY_RANGE[bucket]
    days_out = {
        "0-30":   random.randint(1, 30),
        "31-60":  random.randint(31, 60),
        "61-90":  random.randint(61, 90),
        "91-120": random.randint(91, 120),
        "120+":   random.randint(121, 365),
    }[bucket]

    ar_rows.append(Row(
        ar_id             = f"AR-{i:07d}",
        claim_id          = c.claim_id,
        member_id         = c.member_id,
        provider_id       = c.provider_id,
        service_date      = c.service_date,
        balance_amount    = round(c.billed_amount * random.uniform(0.40, 1.10), 2),
        lob               = c.lob,
        state             = c.state,
        aging_bucket      = bucket,
        days_outstanding  = days_out,
        recovery_score    = round(random.uniform(lo, hi), 4),
        denial_related    = c.claim_status == "DENIED",
        last_worked_date  = str(rand_date(date(2024,1,1), date(2025,6,1))),
    ))

df_ar = spark.createDataFrame(ar_rows)
df_ar.write.format("delta").mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.gold_ar_aging")
print(f"✓ gold_ar_aging: {df_ar.count():,} rows")

# COMMAND ----------

# MAGIC %md ### 3g. Gold: Budget vs Actuals (288 rows — 24 months × 12 departments)

# COMMAND ----------

budget_rows = []
for year in [2024, 2025]:
    for month in range(1, 13):
        for dept in DEPTS:
            base = random.uniform(80_000, 2_000_000)
            budget = round(base, 2)
            # Add realistic variance: ±5% on average, occasional spikes
            variance_factor = random.gauss(1.0, 0.04)
            actuals = round(budget * variance_factor, 2)
            budget_rows.append(Row(
                period         = f"{year}-{month:02d}",
                year           = year,
                month          = month,
                department     = dept,
                budget_amount  = budget,
                actual_amount  = actuals,
                variance_amount= round(actuals - budget, 2),
                variance_pct   = round((actuals - budget) / budget * 100, 2),
            ))

df_budget = spark.createDataFrame(budget_rows)
df_budget.write.format("delta").mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.gold_budget_actuals")
print(f"✓ gold_budget_actuals: {df_budget.count():,} rows")

# COMMAND ----------

# MAGIC %md ### 3h. Gold: KPI Daily (730 rows — 2024–2025)

# COMMAND ----------

from datetime import datetime

kpi_rows = []
start = date(2024, 1, 1)
for day_idx in range(730):
    kpi_date = start + timedelta(days=day_idx)
    mo = kpi_date.month

    # Denial rate: starts ~6.8%, improves to ~5.5% with seasonal spikes in Jan
    denial_rate = round(
        0.068 - (day_idx * 0.013 / 730)
        + (0.010 if mo == 1 else 0.0)
        + (0.005 if mo in (6, 7) else 0.0)
        + random.gauss(0, 0.002),
        4
    )
    # Collection rate: starts ~88%, trends up to ~92%
    collection_rate = round(
        0.880 + (day_idx * 0.040 / 730)
        + random.gauss(0, 0.005),
        4
    )
    # Days in AR: starts ~42, improves to ~35
    days_in_ar = round(
        42 - (day_idx * 7 / 730)
        + random.gauss(0, 1.5),
        1
    )
    # Claims received per day
    claims_received = int(random.gauss(120, 15) + (30 if mo == 1 else 0))

    kpi_rows.append(Row(
        kpi_date          = str(kpi_date),
        year              = kpi_date.year,
        month             = mo,
        denial_rate       = max(0.02, denial_rate),
        collection_rate   = min(0.99, max(0.70, collection_rate)),
        avg_days_in_ar    = max(20.0, days_in_ar),
        claims_received   = max(50, claims_received),
        claims_paid       = int(claims_received * collection_rate),
        claims_denied     = int(claims_received * denial_rate),
    ))

df_kpi = spark.createDataFrame(kpi_rows)
df_kpi.write.format("delta").mode("overwrite").saveAsTable(f"{CATALOG}.{SCHEMA}.gold_kpi_daily")
print(f"✓ gold_kpi_daily: {df_kpi.count():,} rows")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 4: Verify All Tables

# COMMAND ----------

# MAGIC %sql
# MAGIC SHOW TABLES;

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 5: Explore with `display()`
# MAGIC
# MAGIC `display()` is Databricks' built-in way to render DataFrames and SQL results
# MAGIC as interactive tables with sorting, filtering, and charts.

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Preview claims with member and provider info joined
# MAGIC SELECT
# MAGIC   c.claim_id,
# MAGIC   m.first_name || ' ' || m.last_name AS member_name,
# MAGIC   c.lob,
# MAGIC   c.state,
# MAGIC   c.claim_type,
# MAGIC   c.billed_amount,
# MAGIC   c.paid_amount,
# MAGIC   c.claim_status,
# MAGIC   c.denial_category
# MAGIC FROM bronze_claims c
# MAGIC JOIN bronze_members m ON c.member_id = m.member_id
# MAGIC LIMIT 100;

# COMMAND ----------

# MAGIC %md ## Step 6: Inspect Delta Table Metadata

# COMMAND ----------

# MAGIC %sql
# MAGIC DESCRIBE DETAIL bronze_claims;

# COMMAND ----------

# MAGIC %sql
# MAGIC DESCRIBE HISTORY bronze_claims;

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 7: Schema Evolution — Add an Audit Column
# MAGIC
# MAGIC Delta Lake supports schema evolution out of the box.
# MAGIC Adding a column is non-destructive — existing data gets NULL for that column.

# COMMAND ----------

# MAGIC %sql
# MAGIC ALTER TABLE bronze_claims ADD COLUMN load_timestamp TIMESTAMP;
# MAGIC
# MAGIC -- Backfill with current time for existing rows
# MAGIC UPDATE bronze_claims SET load_timestamp = CURRENT_TIMESTAMP() WHERE load_timestamp IS NULL;
# MAGIC
# MAGIC -- Verify
# MAGIC SELECT claim_id, claim_status, load_timestamp FROM bronze_claims LIMIT 5;

# COMMAND ----------

# MAGIC %md
# MAGIC ---
# MAGIC ## ✅ Notebook 00 Complete!
# MAGIC
# MAGIC All 8 tables are created and loaded. Continue to:
# MAGIC - **`01_sql_basics.sql`** — open in the SQL Editor for hands-on finance analytics
# MAGIC
# MAGIC ---
# MAGIC ## 📝 TODOs — Try These Yourself
# MAGIC
# MAGIC **TODO 1:** The `ALTER TABLE` above added `load_timestamp` to `bronze_claims`.
# MAGIC Do the same for `bronze_members` — add a `created_at TIMESTAMP` column and backfill it.
# MAGIC
# MAGIC **TODO 2:** Use `display()` to show the **top 10 members by total billed amount**.
# MAGIC *(Hint: use a `%sql` cell with GROUP BY and ORDER BY)*
# MAGIC
# MAGIC **TODO 3:** How many **distinct providers** are in your dataset?
# MAGIC Write a SQL cell that returns the count, broken down by `specialty`.
