-- ===========================
-- PHASE 3: THE SQL RECONCILIATION ENGINE
-- ========================================================================
-- ------------------------------------------------------------------------
-- STEP 0: IMPORT VERIFICATION
-- ------------------------------------------------------------------------
-- Business Question: Did the MySQL Import Wizard drop any records during the CSV ingestion process due to data type mismatches?
-- ========================================================================

Select 'legacy' as SystemName,
		Count(*) as Total_rows
from legacy_sales
Union ALL
Select 'cloud' as SystemName,
		Count(*) as Total_rows
from cloud_sales;

-- Result:
-- SystemName | Total_rows   
-- legacy	  | 56046
-- cloud	  | 55986


-- ========================================================================
-- ------------------------------------------------------------------------
-- TEST 1: THE COMPLETENESS CHECK (API TIMEOUTS)
-- ------------------------------------------------------------------------
-- Business Question: Did every order from the Legacy CRM successfully make it to the new Cloud Data Warehouse?
-- ------------------------------------------------------------------------
-- ========================================================================

Select l.OrderNumber, l.OrderDate, l.OrderQuantity, l.OrderLineItem, 'MISSING IN CLOUD' as error_type
from legacy_sales l
Left Join cloud_sales c
on c.OrderNumber = l.OrderNumber
AND c.OrderLineItem = l.OrderLineItem
where c.OrderNumber is NULL;

-- Result:
-- OrderNumber | OrderDate   | OrderQuantity  | OrderLineItem  | error_type
-- SO45856	   | 2020-04-07	 | 1              | 1	 		   | MISSING IN CLOUD
-- SO46188	   | 2020-05-12	 | 1              | 1	 		   | MISSING IN CLOUD
-- SO47281	   | 2020-08-25	 | 1              | 1	 		   | MISSING IN CLOUD
-- ... (Total 60 rows)

-- ------------------------------------------------------------------------
-- TEST 2: VALUE INTEGRITY CHECK (CORRUPTED QUANTITIES)
-- ------------------------------------------------------------------------
-- Business Question: Are order quantities in the cloud system accurate?
-- ------------------------------------------------------------------------

Select l.OrderNumber,
		l.OrderQuantity as legacy_quantity,
		c.OrderQuantity as cloud_quantity,
		ABS(l.OrderQuantity - c.OrderQuantity) as quantity_variance,
		CASE
			When l.OrderQuantity > c.OrderQuantity THEN 'UnderCounted'
			When l.OrderQuantity < c.OrderQuantity THEN 'OverCounted'
		END as Variance_direction
from legacy_sales l
Join cloud_sales c
on c.OrderNumber = l.OrderNumber
AND c.OrderLineItem = l.OrderLineItem
where c.OrderQuantity != l.OrderQuantity;

-- Result:
-- OrderNumber | legacy_quantity | cloud_quantity | quantity_variance | Variance_direction
-- SO54361	   | 1				 | 3              | 2	 			  | OverCounted
-- SO54615	   | 2				 | 1              | 1	 			  | UnderCounted
-- SO55819	   | 2				 | 4              | 2	 			  | OverCounted
-- ... (Total 26 rows)



-- ------------------------------------------------------------------------
-- TEST 3: THE BUSINESS IMPACT (UNIT EXPOSURE ANALYSIS)
-- ------------------------------------------------------------------------
-- Business Question: What is the total physical volume of products completely 
-- lost or mathematically corrupted due to the migration failure?
-- ------------------------------------------------------------------------

With Missing_Units as (
	Select COALESCE(SUM(l.OrderQuantity), 0) as missing_quantity
	from legacy_sales l
	LEFT JOIN cloud_sales c 
        ON l.OrderNumber = c.OrderNumber 
        AND l.OrderLineItem = c.OrderLineItem
    WHERE c.OrderNumber IS NULL
	),
Corrupted_Units as (
	Select COALESCE(sum(abs(l.OrderQuantity - c.OrderQuantity)), 0) as corrupted_quantity
	from legacy_sales l
	Join cloud_sales c on
	c.OrderNumber = l.OrderNumber AND c.OrderLineItem = l.OrderLineItem
	where l.OrderQuantity != c.OrderQuantity
	)
Select 
	missing_quantity as Total_Missing_Units,
	corrupted_quantity as Total_Corrupted_Quantity,
	(missing_quantity + corrupted_quantity) as Total_Units_at_risk
	from Missing_Units, Corrupted_Units;

-- Result:
-- Total_Missing_Units | Total_Corrupted_Quantity | Total_Units_risk
-- 88 				   | 33    					  | 121
