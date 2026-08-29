/* ============================================================
   MARKETING ANALYTICS PROJECT
   SQL DATA CLEANING & ANALYTICAL VIEWS
   ============================================================

   Database:
       MarketingAnalytics

   Purpose:
       Create cleaned and standardized SQL views that will be
       used as the analytical data source for Power BI.

   Raw tables:
       dbo.customers
       dbo.geography
       dbo.products
       dbo.customer_reviews
       dbo.engagement_data
       dbo.customer_journey

   Analytical views:
       dbo.dim_customer
       dbo.dim_product
       dbo.fact_customer_reviews
       dbo.fact_engagement_data
       dbo.fact_customer_journey
   ============================================================ */


/* ============================================================
   STEP 1 — SELECT DATABASE
   ============================================================ */

USE MarketingAnalytics;
GO


/* ============================================================
   STEP 2 — CUSTOMER DIMENSION
   View: dbo.dim_customer

   Objective:
       Enrich customer information with geographic information.

   Transformations:
       - Join customers with geography.
       - Keep all customers using LEFT JOIN.
       - Add City and Country attributes.
   ============================================================ */

CREATE OR ALTER VIEW dbo.dim_customer
AS

SELECT
    c.CustomerID,
    c.CustomerName,
    c.Email,
    c.Age,
    c.Gender,
    c.GeographyID,
    g.City,
    g.Country

FROM dbo.customers AS c

LEFT JOIN dbo.geography AS g
    ON c.GeographyID = g.GeographyID;

GO


/* ============================================================
   STEP 3 — PRODUCT DIMENSION
   View: dbo.dim_product

   Objective:
       Categorize products according to their price.

   Price categories:
       Low       : Price < 50
       Medium    : Price between 50 and 200
       High      : Price > 200
   ============================================================ */

CREATE OR ALTER VIEW dbo.dim_product
AS

SELECT
    ProductID,
    ProductName,
    Price,

    CASE
        WHEN Price < 50 THEN 'Low'
        WHEN Price BETWEEN 50 AND 200 THEN 'Medium'
        ELSE 'High'
    END AS PriceCategory

FROM dbo.products;

GO


/* ============================================================
   STEP 4 — CUSTOMER REVIEWS FACT
   View: dbo.fact_customer_reviews

   Objective:
       Clean customer review text.

   Transformations:
       - Remove redundant double spaces.
       - Keep review date as DATE.
       - Keep rating and customer/product relationships.
   ============================================================ */

CREATE OR ALTER VIEW dbo.fact_customer_reviews
AS

SELECT
    ReviewID,
    CustomerID,
    ProductID,
    CONVERT(DATE, ReviewDate) AS ReviewDate,
    Rating,

    -- Remove redundant spaces
    REPLACE(ReviewText, '  ', ' ') AS ReviewText

FROM dbo.customer_reviews;

GO


/* ============================================================
   STEP 5 — ENGAGEMENT FACT
   View: dbo.fact_engagement_data

   Objective:
       Clean and normalize engagement data.

   Transformations:
       - Standardize ContentType.
       - Convert "Socialmedia" to "Social Media".
       - Extract Views from ViewsClicksCombined.
       - Extract Clicks from ViewsClicksCombined.
       - Convert Views and Clicks to numeric values.
       - Exclude Newsletter records.
       - Keep EngagementDate as DATE.

   Example:
       ViewsClicksCombined = '1500-250'

       Views  = 1500
       Clicks = 250
   ============================================================ */

CREATE OR ALTER VIEW dbo.fact_engagement_data
AS

SELECT
    EngagementID,
    ContentID,
    CampaignID,
    ProductID,
    Likes,

    -- Standardize content type
    UPPER(
        REPLACE(ContentType, 'Socialmedia', 'Social Media')
    ) AS ContentType,

    -- Extract and convert Views to integer
    TRY_CONVERT(
        INT,
        LEFT(
            ViewsClicksCombined,
            CHARINDEX('-', ViewsClicksCombined) - 1
        )
    ) AS Views,

    -- Extract and convert Clicks to integer
    TRY_CONVERT(
        INT,
        RIGHT(
            ViewsClicksCombined,
            LEN(ViewsClicksCombined)
            - CHARINDEX('-', ViewsClicksCombined)
        )
    ) AS Clicks,

    -- Keep date in DATE format for Power BI
    CONVERT(DATE, EngagementDate) AS EngagementDate

FROM dbo.engagement_data

WHERE ContentType <> 'Newsletter';

GO


/* ============================================================
   STEP 6 — CUSTOMER JOURNEY FACT
   View: dbo.fact_customer_journey

   Objective:
       Clean, standardize and deduplicate customer journey data.

   Transformations:
       1. Convert Stage to uppercase.
       2. Identify duplicate records.
       3. Keep only the first occurrence of each duplicate.
       4. Calculate average duration by VisitDate.
       5. Replace missing Duration values with the average
          duration for that VisitDate.

   Duplicate definition:
       Same:
           CustomerID
           ProductID
           VisitDate
           Stage
           Action
   ============================================================ */

CREATE OR ALTER VIEW dbo.fact_customer_journey
AS

SELECT
    JourneyID,
    CustomerID,
    ProductID,
    VisitDate,
    Stage,
    Action,

    -- Replace NULL Duration with average duration
    COALESCE(Duration, avg_duration) AS Duration

FROM
(
    SELECT
        JourneyID,
        CustomerID,
        ProductID,
        VisitDate,

        -- Standardize Stage values
        UPPER(Stage) AS Stage,

        Action,
        Duration,

        -- Calculate average duration for each visit date
        AVG(Duration) OVER (
            PARTITION BY VisitDate
        ) AS avg_duration,

        -- Identify duplicate records
        ROW_NUMBER() OVER
        (
            PARTITION BY
                CustomerID,
                ProductID,
                VisitDate,
                UPPER(Stage),
                Action

            ORDER BY JourneyID
        ) AS row_num

    FROM dbo.customer_journey
) AS cleaned_data

-- Keep only the first record from each duplicate group
WHERE row_num = 1;

GO


/* ============================================================
   STEP 7 — VERIFY CREATED VIEWS
   ============================================================ */

SELECT *
FROM dbo.dim_customer;

SELECT *
FROM dbo.dim_product;

SELECT *
FROM dbo.fact_customer_reviews;

SELECT *
FROM dbo.fact_engagement_data;

SELECT *
FROM dbo.fact_customer_journey;

GO


/* ============================================================
   STEP 8 — DATA QUALITY CHECKS
   ============================================================ */


/* ------------------------------------------------------------
   Check number of records in each analytical view
   ------------------------------------------------------------ */

SELECT
    'dim_customer' AS ViewName,
    COUNT(*) AS RecordCount
FROM dbo.dim_customer

UNION ALL

SELECT
    'dim_product',
    COUNT(*)
FROM dbo.dim_product

UNION ALL

SELECT
    'fact_customer_reviews',
    COUNT(*)
FROM dbo.fact_customer_reviews

UNION ALL

SELECT
    'fact_engagement_data',
    COUNT(*)
FROM dbo.fact_engagement_data

UNION ALL

SELECT
    'fact_customer_journey',
    COUNT(*)
FROM dbo.fact_customer_journey;


/* ------------------------------------------------------------
   Check for remaining duplicate customer journey records
   ------------------------------------------------------------ */

SELECT
    CustomerID,
    ProductID,
    VisitDate,
    Stage,
    Action,
    COUNT(*) AS RecordCount

FROM dbo.fact_customer_journey

GROUP BY
    CustomerID,
    ProductID,
    VisitDate,
    Stage,
    Action

HAVING COUNT(*) > 1;


/* ------------------------------------------------------------
   Check for NULL Duration values
   ------------------------------------------------------------ */

SELECT
    COUNT(*) AS NullDurationCount

FROM dbo.fact_customer_journey

WHERE Duration IS NULL;


/* ------------------------------------------------------------
   Check for NULL customer geography
   ------------------------------------------------------------ */

SELECT
    COUNT(*) AS CustomersWithoutGeography

FROM dbo.dim_customer

WHERE City IS NULL
   OR Country IS NULL;


/* ------------------------------------------------------------
   Check engagement records
   ------------------------------------------------------------ */

SELECT
    COUNT(*) AS NewsletterRecords

FROM dbo.fact_engagement_data

WHERE ContentType = 'NEWSLETTER';


/* ============================================================
   END OF SCRIPT
   ============================================================ */