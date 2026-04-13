# Cloud Migration Data Reconciliation Audit

## Objective
Design a DataOps reconciliation system to detect and remediate data integrity failures during a legacy CRM to cloud warehouse migration.

The system identifies:
- Missing records (completeness failures)
- Quantity discrepancies (value corruption)

Using forensic SQL validation and operational dashboards.

## System Architecture & Audit Scope
* **Source System:** Legacy CRM (Source of Truth)
* **Target System:** Cloud Data Warehouse 
* **Migration Type:** Batch ETL 
* **Primary Key:** `(OrderNumber, OrderLineItem)`
* **Grain:** One row per order line item. 
* **Scope Definition:** This audit prioritizes Completeness (dropped records) and Value Integrity (accuracy of migrated quantities). Duplicate validation and schema drift checks are recommended as secondary extensions.
* **Performance Note:** All forensic joins were executed on composite keys (`OrderNumber`, `OrderLineItem`) simulating indexed environments to ensure audit queries remain highly scalable for multi-million row datasets.
  
This audit design mirrors real-world data validation layers used in ETL pipelines before financial reporting systems.

## Methodology

### Phase 1: Controlled Anomaly Injection (Python)
Created a ground truth dataset from 3 years of sales data (56,046 records) and simulated two real-world migration failures:
* **Completeness Error:** 60 records dropped.
* **Quantity Discrepancy:** 40 records with mutated quantities.


👉 | [View the Python Anomaly Injection Script](./python/migration_sabotage.py) |


### Phase 2: Forensic SQL Analysis (MySQL)

👉 | [View the Master Forensic SQL Script](./sql/reconciliation_audit.sql) |

**Test 1 — Completeness Check**
```sql
SELECT 
    l.OrderNumber, 
    l.OrderDate, 
    l.OrderQuantity,
    l.OrderLineItem,        
    'MISSING IN CLOUD' as error_type
FROM legacy_sales l
LEFT JOIN cloud_sales c
    ON c.OrderNumber = l.OrderNumber   
    AND c.OrderLineItem = l.OrderLineItem
WHERE c.OrderNumber IS NULL;
```
> **Result:** 60 orphan records identified (88 units completely lost).

**Test 2 — Quantity Discrepancy Check**
```sql
SELECT 
    l.OrderNumber,
    l.OrderQuantity as legacy_quantity,
    c.OrderQuantity as cloud_quantity,
    ABS(l.OrderQuantity - c.OrderQuantity) as quantity_variance,
    CASE 
        WHEN l.OrderQuantity > c.OrderQuantity THEN 'UnderCounted'
        WHEN l.OrderQuantity < c.OrderQuantity THEN 'OverCounted'
    END as Variance_direction
FROM legacy_sales l
JOIN cloud_sales c
    ON c.OrderNumber = l.OrderNumber 
    AND c.OrderLineItem = l.OrderLineItem
WHERE c.OrderQuantity != l.OrderQuantity;
```
> **Result:** 26 corrupted records identified (33 units affected).

> Note: SQL detects 26 of the 40 injected corruptions. The remaining 14 fall within deleted records, meaning they are removed before value validation — demonstrating how missing records can mask downstream corruption in real-world migrations.

**Test 3 — Business Impact (CTE)**
```sql
WITH Missing_Units AS (
    SELECT COALESCE(SUM(l.OrderQuantity), 0) as missing_quantity
    FROM legacy_sales l
    LEFT JOIN cloud_sales c 
        ON l.OrderNumber = c.OrderNumber 
        AND l.OrderLineItem = c.OrderLineItem
    WHERE c.OrderNumber IS NULL
),
Corrupted_Units AS (
    SELECT COALESCE(SUM(ABS(l.OrderQuantity - c.OrderQuantity)), 0) as corrupted_quantity
    FROM legacy_sales l
    JOIN cloud_sales c 
        ON c.OrderNumber = l.OrderNumber 
        AND c.OrderLineItem = l.OrderLineItem
    WHERE l.OrderQuantity != c.OrderQuantity
)
SELECT 
    missing_quantity as Total_Missing_Units,
    corrupted_quantity as Total_Corrupted_Quantity,
    (missing_quantity + corrupted_quantity) as Total_Units_at_Risk
FROM Missing_Units, Corrupted_Units;
```
> **Result:** 121 total units exposed to risk.

## Root Cause Analysis (Simulated Failure Mapping)
Detection is only the first step. Based on the audit signatures, the following root causes and fixes were mapped:

| Issue Type | Root Cause Analysis | Remediation Strategy |
| :--- | :--- | :--- |
| **Missing Records** | API timeout/packet drop during peak batch load. | Implement exponential backoff retry logic + robust logging. |
| **Quantity Discrepancy** | Data type mismatch/truncation during migration. | Enforce strict schema validation before warehouse ingestion. |

## Operational Impact (Power BI Dashboard)
Built a 2-page, split-audience DataOps application to transition from analysis to action.

### Page 1 — Executive Audit Summary
KPI tracking and temporal distribution of data loss.

<br>

![Executive Summary Dashboard](dashboard/Executive_summary.png)
<br>

### Page 2 — Operations Action Log
Enables immediate remediation:

- Execute INSERT scripts to recover 60 missing records (88 units)
- Execute UPDATE scripts to correct 26 corrupted records (33 units)
- Prioritize undercounted records to prevent financial underreporting before close

<br>

![Operations Actions log](dashboard/Operations_log.png)
<br>

## Key Findings & Risk Severity Framing

| Metric | Value | Business Impact |
| :--- | :--- | :--- |
| **Missing Records** | 60 orders | 88 units completely lost in transit. |
| **Corrupted Records** | 26 orders | 33 units with quantity mutations. |
| **Total Units at Risk** | 121 units | Material inventory/financial discrepancy requiring immediate correction. |
| **Record Completeness Score** | 99.89% | Measures record migration completeness *(excludes value variance).* |
| **Value Integrity Score** | 99.95% | Measures correctness of migrated values (excludes missing records). |
| **Severity Risk** | High | Despite a high integrity percentage, failures distributed across 19 months, with peaks in Jan 2022 and Q4 2021 — indicating systemic migration inconsistencies rather than a localized outage. |

### Metric Definitions

- **Record Completeness Score**
  = (Total Records - Missing Records) / Total Records  
  → Measures whether all legacy records were successfully migrated (does NOT account for value correctness)

- **Value Integrity Score**
  = (Matched Quantity Records / Total Matched Records)  
  → Measures correctness of migrated values (excludes missing records)

- **Total Units at Risk**
  = Missing Units + Corrupted Units  
  → Represents total financial/data exposure

## Live Deployment
* 📊 **[Interact with the Live Power BI Dashboard](https://tinyurl.com/reconciliation-project-ritwik)**

## Author
**Sai Ritwik Jannu** — Data Analyst | Hyderabad, India
* 🔗 **[LinkedIn](https://www.linkedin.com/in/sai-ritwik-dataanalyst/)**
```
