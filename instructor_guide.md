# Instructor Guide — Finance Team Databricks Workshop

**Duration:** 2 hours | **Audience:** Finance analysts, AR/billing/coding staff

---

## Pre-Session Checklist (30 min before)

- [ ] Confirm all attendees have a Databricks Free Edition workspace or provisioned access
- [ ] Run `00_setup_and_ingestion.py` yourself to confirm data generates cleanly (~3 min)
- [ ] Have `01_sql_basics.sql` open in the SQL Editor, schema already set
- [ ] Have `04_metric_views.sql` ready to run — metric view creation takes ~15 seconds
- [ ] Pre-create the Genie space so you can demo it immediately (setup takes 5 min)
- [ ] Prepare a dashboard with the 4 datasets loaded so you can build widgets live
- [ ] Test Genie Code: open the SQL Editor, click the Genie Code icon (right panel)
- [ ] Have slide deck ready for Segments 1 and 8

---

## Segment-by-Segment Talk Track

### Segment 1: Intro & Orientation (15 min)

**Key messages:**
1. *"Databricks isn't just a data warehouse — it's the place where raw data becomes finance insight, and where AI meets governance."*
2. Walk the left nav: Catalog → Notebooks → SQL Editor → Dashboards → Genie → Workflows
3. Introduce the RCM scenario: *"Imagine you're an AR analyst on the finance team. You receive 835 remittance files. Claims are denied. AR is aging. You need to know where to focus your team."*
4. Draw the Medallion Architecture on a whiteboard or slide:
   - **Bronze:** raw 835s and claims off the payer portal (dirty, complete, auditable)
   - **Silver:** cleaned, deduped, enriched with provider tier and LOB
   - **Gold:** AR aging buckets, budget vs actuals, KPI dashboards

**Common question:** *"Do we need to use the Medallion Architecture?"*
> No, but it's the pattern that scales. Bronze preserves everything for audit. Silver is your "clean room." Gold is what finance users query. You can start with just Silver + Gold.

---

### Segment 2: Notebooks (20 min)

**Talking points for `00_setup_and_ingestion.py`:**
- Show the `%md` / `%sql` / Python cell types — explain cell magic
- When you run `display(df)`, show the chart icon and click into it
- When showing `DESCRIBE HISTORY`, point out the version numbers — *"this is how you time-travel"*

**Live demo moment:** After `DESCRIBE HISTORY` run:
```sql
SELECT * FROM bronze_claims VERSION AS OF 0 LIMIT 5;
```
Then: `SELECT * FROM bronze_claims LIMIT 5;` to show the difference after adding `load_timestamp`.

**If someone finishes TODOs early:** Ask them to try `RESTORE TABLE bronze_claims TO VERSION AS OF 0` — shows Delta Lake's time-travel restore capability.

---

### Segment 3: SQL Editor (30 min)

**Talking points:**
- The SQL Editor is NOT a notebook — no Python, no `%sql` magic. Pure SQL.
- Keyboard shortcut: `Ctrl+Shift+Enter` runs the current query (highlighted or cursor-selected)
- Show the "Results" panel — sortable, exportable to CSV
- Show the "Query history" in the left panel — every query is logged with user, duration, cost

**Pacing for Part A (basics):**
- Run query 1a (claim counts) together, then let attendees try TODO 4 themselves (3 min)
- Run query 3b (billed/paid by state) as a group — this is the most relatable to their daily work

**Pacing for Part B (advanced):**
- Build the CTE together (query 1a in `03_advanced_analytics.sql`) — narrate each WITH block
- Run the LAG query (2a) — show the `prev_month_rate` and `trend` columns
- Let attendees work on TODO 7 (at-risk flagging) for 5 min

**Common question:** *"When do I use a CTE vs a subquery?"*
> CTEs are just named subqueries with a cleaner syntax. Use CTEs when you reference the same subresult more than once, or when your query is hard to read. They don't change performance in Databricks.

---

### Segment 4: Genie Code (15 min)

**Setup:** Open SQL Editor → look for the Genie icon or AI assistant in the right panel

**Demo script:**
1. Type the prompt, show the generated SQL appearing token by token
2. Before running it, read through the SQL with the group: *"Let's make sure this is right — what is it doing?"*
3. Run it, validate the result
4. Modify the prompt: *"Add a filter for MA only"* — show how it adjusts the SQL

**Key message:** *"This is a co-pilot, not autopilot. You still need to understand SQL to validate what it generates. But it gets you from zero to draft in 10 seconds."*

**Common question:** *"Can Genie Code see my actual data?"*
> It sees the schema and column names, not the data values. It uses the column names and comments to understand what the data means — which is why good naming and comments matter.

---

### Segment 5: Metric Views (20 min)

**Motivating the concept (2 min before the SQL):**
> *"Without a metric view, Genie has to guess. If someone asks 'what's our denial rate?', Genie has to figure out which table, which column, and how to calculate it. With a metric view, you've told it exactly what 'denial rate' means — and it will answer the same way every time."*

**Walk through the YAML sections:**
- `source:` → this is your fact table (gold_ar_aging)
- `joins:` → the dimension tables to pull in (silver_claims, silver_denials)
- `dimensions:` → what you GROUP BY (lob, state, aging_bucket...)
- `measures:` → the numbers and how to calculate them

**After creation, run query 3a together:**
```sql
SELECT lob, MEASURE(denial_rate), MEASURE(total_ar_balance)
FROM mv_rcm_finance GROUP BY lob;
```
Point out: `MEASURE()` is the new aggregate function for metric views. Without it, you'd get an error.

**Common question:** *"What happens if I query the view without MEASURE()?"*
> You get a SQL error. Metric views enforce that measures go through `MEASURE()` — this prevents misuse and ensures consistent aggregation.

---

### Segment 6: Dashboards (20 min)

**Pre-load:** Have the `ds_claims_trend` dataset already created before the session so you can focus on widget building.

**Walk through Widget 1 live:**
1. Add dataset → paste query → name it → save
2. Add widget → select chart type → pick dataset → configure axes
3. Change the chart type and show how quickly it re-renders

**For the global date filter:**
- Add a filter widget → Date Range type
- Connect to `service_month` on `ds_claims_trend`
- Show how changing the filter updates all connected widgets

**Talking point:** *"This is what self-service BI looks like in Databricks. No Tableau license, no IT ticket. Your finance team can build this themselves — and because it's on the same platform as your data, there's no export step, no stale CSV."*

---

### Segment 7: Genie Space (10 min)

**Pre-create the space before the session.** Add all tables + metric view + instructions.

**Demo questions (have these typed and ready to paste):**
1. *"What is the denial rate for prior auth claims by state in 2024?"*
2. *"Show me the AR aging trend for Medicare Advantage over the last 12 months"*
3. *"Which providers have the highest at-risk AR balance?"*

**After each answer:** scroll down to show "Here's the SQL behind this answer" — click it, show the SQL.

**Key message:** *"The metric view is why these answers are accurate. Without it, Genie might use the wrong table or the wrong calculation for 'denial rate'. With it, every answer is consistent and auditable."*

---

### Segment 8: Governance (10 min)

**Navigation demo:**
1. Catalog (left nav) → expand `main` → expand your schema → click `bronze_members`
2. Show: columns tab (names, types, comments), lineage tab, permissions tab

**For column masking:** This requires a Unity Catalog workspace with masking policies configured. On Free Edition, show the concept via slides instead.
> *"In a governed workspace, I can define a masking policy so that `member_dob` shows as `****` for anyone without the 'PHI_ACCESS' group. The data is there — it's just hidden based on your identity."*

**Lineage talking point:**
> *"This is your SOX compliance story. When auditors ask 'where did this number come from?', you click the lineage tab and show them: gold_ar_aging came from silver_claims, which came from bronze_claims, which was loaded at 6:00 AM on the 1st. Every step, every transformation, fully tracked."*

---

### Segment 9: Workflows (10 min)

**Live build (do this fast — audience should watch, not build):**
1. Workflows → Create Job → name it `finance_month_end_pipeline`
2. Add Task 1: bronze_refresh → Notebook → select `00_setup_and_ingestion`
3. Add Task 2: silver_transform → Notebook → select `06_workflow_demo` → set dependency on Task 1
4. Add Task 3: gold_refresh → SQL → select `05_dashboard_setup.sql` → depends on Task 2
5. Set schedule: `0 6 1 * *` → Chicago timezone
6. Add email alert → On failure

**Don't run it live** (takes 3–5 min). Instead, show a screenshot of a successful run graph.

**Closing message:**
> *"This is the automation story. No one on your team should be manually running reports on the 1st of the month anymore. You schedule the pipeline, set up the alert, and the dashboard is fresh when you open it Monday morning."*

---

## Answers to All 24 TODOs

### TODO 1
```sql
ALTER TABLE bronze_members ADD COLUMN created_at TIMESTAMP;
UPDATE bronze_members SET created_at = CURRENT_TIMESTAMP() WHERE created_at IS NULL;
```

### TODO 2
```sql
SELECT member_id, SUM(billed_amount) AS total_billed
FROM silver_claims GROUP BY member_id ORDER BY total_billed DESC LIMIT 10;
```

### TODO 3
```sql
SELECT specialty, COUNT(DISTINCT provider_id) AS provider_count
FROM bronze_providers GROUP BY specialty ORDER BY provider_count DESC;
```

### TODO 4
```sql
SELECT claim_type, ROUND(AVG(days_to_submit), 1) AS avg_days_to_submit
FROM silver_claims WHERE claim_status = 'PAID'
GROUP BY claim_type ORDER BY avg_days_to_submit DESC;
```

### TODO 5
```sql
WITH lob_denial AS (
  SELECT lob, denial_category, COUNT(*) AS cnt
  FROM silver_claims WHERE claim_status = 'DENIED' GROUP BY lob, denial_category
),
ranked AS (
  SELECT *, RANK() OVER (PARTITION BY lob ORDER BY cnt DESC) AS rk FROM lob_denial
)
SELECT lob, denial_category AS top_denial_category, cnt
FROM ranked WHERE rk = 1;
```

### TODO 6
```sql
SELECT c.state,
  COUNT(*) AS total_claims,
  COUNT(CASE WHEN NOT p.is_network THEN 1 END) AS oon_claims,
  ROUND(COUNT(CASE WHEN NOT p.is_network THEN 1 END) * 100.0 / COUNT(*), 2) AS oon_pct
FROM silver_claims c JOIN bronze_providers p ON c.provider_id = p.provider_id
GROUP BY c.state ORDER BY oon_pct DESC;
```

### TODO 7
Add to the `at_risk` CTE:
```sql
CASE WHEN balance_amount > 10000 AND aging_bucket = '120+' THEN TRUE ELSE FALSE END AS is_high_value_risk
```

### TODO 8
```sql
AVG(denial_rate_pct) OVER (PARTITION BY state, specialty) AS state_specialty_avg_denial_rate
```

### TODO 9
```sql
WITH monthly_avg AS (
  SELECT DATE_TRUNC('month', CAST(kpi_date AS DATE)) AS month,
    AVG(AVG(collection_rate) OVER (ORDER BY kpi_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)) AS avg_rolling_cr
  FROM gold_kpi_daily GROUP BY 1
) SELECT * FROM monthly_avg WHERE avg_rolling_cr < 0.88 ORDER BY month;
```

### TODO 10 (Genie Code)
Prompt: *"Show monthly collection rate trend for Medicare Advantage claims in 2024"*
Expected SQL: GROUP BY service_month filtered to lob='MA' and year=2024, with SUM(paid_amount)/SUM(billed_amount).

### TODO 11 (Genie Code)
Follow-up prompt: *"Add a year-over-year comparison column comparing 2024 to 2023"*
Expected: LAG with PARTITION BY month, ORDER BY year.

### TODO 12 (Metric View)
```yaml
  - name: is_high_value_risk
    expr: "CASE WHEN source.balance_amount > 10000 AND source.aging_bucket = '120+' THEN true ELSE false END"
    comment: "True when balance exceeds $10K and claim has been outstanding 120+ days"
```

### TODO 13 (Metric View)
```yaml
  - name: net_recoverable_amount
    expr: "ROUND(SUM(source.balance_amount * source.recovery_score), 2)"
    comment: "Expected collectible dollars: balance × recovery probability"
```

### TODO 14 (Metric View query)
```sql
SELECT state, lob, MEASURE(denial_rate), MEASURE(collection_rate), MEASURE(total_ar_balance)
FROM mv_rcm_finance
WHERE service_year = 2024 GROUP BY state, lob ORDER BY MEASURE(total_ar_balance) DESC;
```

### TODO 15 (Genie)
Expected: Genie generates a query referencing `mv_rcm_finance` and uses `MEASURE(total_ar_balance)` with `WHERE lob = 'MA' AND aging_bucket = '0-30'`.

### TODO 16 (Dashboard)
Add Widget 5: Line chart, dataset=`ds_kpi_trend`, x=`kpi_date`, y=`rolling_7d_collection_rate`. For the reference line, use Dashboard settings → Reference lines → y=0.90.

### TODO 17 (Dashboard)
Dashboard toolbar → Settings (gear) → Enable cross-filtering → On.

### TODO 18 (Dashboard)
Dashboard toolbar → Refresh schedule → Every 24 hours (at a time of your choice).

### TODO 19 (Dashboard)
Top right → Share → enter email → role = Viewer. Viewers cannot edit, only view.

### TODO 20 (Genie Space)
Add to instructions: *"'High-risk AR' means records where balance_amount > 10000 AND aging_bucket = '120+' AND recovery_score < 0.20."*

### TODO 21 (Genie Space)
Prompt: *"Which providers have the highest write-off rate in the last 6 months?"*
Genie should join silver_claims + silver_denials, filter to last 6 months, calculate write_off = denied and not appealed / total claims.

### TODO 22 (Genie Space)
In Genie space → Settings → Trusted Assets → Add Dashboard → select "Finance Operations KPI Dashboard". Users can now see the dashboard directly from Genie answers.

### TODO 23 (Workflow)
Add Task 4: `dashboard_refresh` → SQL notebook `05_dashboard_setup.sql` → depends on `gold_refresh`. Position: after Task 3.

### TODO 24 (Workflow)
In Task 1 settings → Advanced → Timeout: 5 minutes (300 seconds). If exceeded, the task fails and triggers the failure alert. Handle with: catch the timeout in the notebook using `try/except` or add a retry policy (Retries: 1, Retry on timeout: True).

---

## Common Questions & Answers

**Q: What's the difference between a notebook and the SQL Editor?**
> Notebooks support multiple languages (Python, SQL, R, Scala) in the same file using `%sql` or `%python` cell magic. The SQL Editor is SQL-only but has a better query-writing experience (autocomplete, schema browser, query history). Use notebooks for data engineering; use the SQL Editor for analytics.

**Q: Can I connect Power BI or Tableau to these tables?**
> Yes. Go to SQL Warehouses → connection details → copy the JDBC/ODBC connection string. Both Power BI and Tableau support native Databricks connectors.

**Q: What is a Serverless SQL Warehouse vs a Classic warehouse?**
> Serverless starts in seconds (no cluster to wait for), scales automatically, and you pay per query second. Classic gives you more control over cluster size but takes 2–3 minutes to start. For Finance use cases, Serverless is recommended.

**Q: How much does this cost?**
> Free Edition is free with usage limits. For a provisioned workspace, SQL queries consume DBUs (Databricks Units). A typical analyst session costs $0.10–$1.00 depending on query complexity and warehouse size. Your admin can see cost attribution in the Account Console.

**Q: Can Genie access data outside our workspace?**
> No. Genie only queries tables in the Databricks workspace it's configured in. It does not make external API calls with your data.

**Q: Is my data secure when using Genie Code?**
> Genie Code sends the query prompt and schema metadata (table/column names) to Anthropic's Claude model. It does NOT send actual row data. Check your organization's AI policy for approval to use AI features.
