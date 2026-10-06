CREATE DATABASE IF NOT EXISTS freshkart_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
  /*  -----------------------------------------------*/
  use freshkart_db;
 /* ── Customers Table ──────────────────────────*/
 CREATE TABLE customers (
    CustomerID      INT             PRIMARY KEY,
    CustomerName    VARCHAR(100)    NOT NULL,
    City            VARCHAR(50)     NOT NULL,
    SignupDate      DATE,
    PilotGroup      VARCHAR(20)     DEFAULT 'Not in Pilot',
    Responded       TINYINT(1)      DEFAULT 0,
    INDEX idx_city       (City),
    INDEX idx_pilot      (PilotGroup)
);
-- ── Products Table ────────────────────────────────────────────
CREATE TABLE products (
    ProductID       VARCHAR(10)     PRIMARY KEY,
    ProductName     VARCHAR(150)    NOT NULL,
    Category        VARCHAR(50)     NOT NULL,
    MRP             DECIMAL(10,2)   NOT NULL,
    INDEX idx_category   (Category)
);
-- ── Transactions Table ────────────────────────────────────────
CREATE TABLE transactions (
    TransactionID   INT             AUTO_INCREMENT PRIMARY KEY,
    InvoiceNo       VARCHAR(20)     NOT NULL,
    InvoiceDate     DATETIME        NOT NULL,
    CustomerID      INT             NULL,           -- NULL = guest checkout
    ProductID       VARCHAR(10)     NOT NULL,
    Quantity        INT             NOT NULL DEFAULT 1,
    UnitPrice       DECIMAL(10,2)   NOT NULL,
    TotalAmount     DECIMAL(10,2)   NOT NULL,
    Store           VARCHAR(10),
    GuestCheckout   TINYINT(1)      DEFAULT 0,
    INDEX idx_customer   (CustomerID),
    INDEX idx_product    (ProductID),
    INDEX idx_date       (InvoiceDate),
    INDEX idx_invoice    (InvoiceNo),

    INDEX idx_store      (Store)
);
USE freshkart_db;
TRUNCATE TABLE customers;
select * from customers;
TRUNCATE TABLE products;
select * from products;
select count(*) from transactions;
SELECT * FROM transactions WHERE InvoiceNo NOT LIKE 'INV%';
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS guest_checkouts
FROM transactions;

/*-- ──────────────────────────────────────────────────────────────After loading, verify row counts:--*/
SELECT 'customers'    AS table_name, COUNT(*) AS total FROM customers
UNION ALL
SELECT 'products',             COUNT(*) FROM products
UNION ALL
SELECT 'transactions',         COUNT(*) FROM transactions;
-- ══════════════════════════════════════════════════════════════
-- QUERY 01 — Overall Business KPI Snapshot
-- Concept  : Aggregate functions (COUNT DISTINCT, SUM, AVG, MIN, MAX)
-- Purpose  : Single-row health check of the entire business
-- ══════════════════════════════════════════════════════════════
SELECT
    COUNT(DISTINCT InvoiceNo)               AS Total_Invoices,
    COUNT(DISTINCT CustomerID)              AS Active_Customers,
    SUM(Quantity)                           AS Total_Items_Sold,
    ROUND(SUM(TotalAmount), 2)              AS Total_Revenue,
    ROUND(AVG(TotalAmount), 2)              AS Avg_Order_Value,
    ROUND(MIN(TotalAmount), 2)              AS Min_Order_Value,
    ROUND(MAX(TotalAmount), 2)              AS Max_Order_Value,
    DATE(MIN(InvoiceDate))                  AS First_Sale_Date,
    DATE(MAX(InvoiceDate))                  AS Last_Sale_Date,
    DATEDIFF(MAX(InvoiceDate),
             MIN(InvoiceDate))              AS Business_Days_Span
FROM transactions
WHERE GuestCheckout = 0;
-- ══════════════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════════════
-- QUERY 02 — Revenue by City
-- Concept  : INNER JOIN + GROUP BY + Window function for share %
-- Purpose  : Compare performance across 3 cities
-- ══════════════════════════════════════════════════════════════
SELECT
    c.City,
    COUNT(DISTINCT t.InvoiceNo)                             AS Total_Orders,
    COUNT(DISTINCT t.CustomerID)                            AS Unique_Customers,
    SUM(t.Quantity)                                         AS Total_Items_Sold,
    ROUND(SUM(t.TotalAmount), 2)                            AS Total_Revenue,
    ROUND(
        SUM(t.TotalAmount) /
        SUM(SUM(t.TotalAmount)) OVER () * 100, 2
    )                                                       AS Revenue_Share_Pct,
    ROUND(AVG(t.TotalAmount), 2)                            AS Avg_Bill_Value,
    ROUND(SUM(t.TotalAmount) /
          COUNT(DISTINCT t.CustomerID), 2)                  AS Revenue_Per_Customer
FROM transactions t
INNER JOIN customers c ON t.CustomerID = c.CustomerID
WHERE c.City IN ('Chennai', 'Coimbatore', 'Madurai')
  AND t.GuestCheckout = 0
GROUP BY c.City
ORDER BY Total_Revenue DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 03 — Revenue by Product Category
-- Concept  : INNER JOIN products + GROUP BY + ORDER BY
-- Purpose  : Find which product category drives most revenue
-- ══════════════════════════════════════════════════════════════
SELECT
    p.Category,
    COUNT(DISTINCT p.ProductID)                             AS Total_Products,
    SUM(t.Quantity)                                         AS Total_Qty_Sold,
    COUNT(DISTINCT t.InvoiceNo)                             AS Total_Orders,
    ROUND(SUM(t.TotalAmount), 2)                            AS Total_Revenue,
    ROUND(
        SUM(t.TotalAmount) /
        SUM(SUM(t.TotalAmount)) OVER () * 100, 2
    )                                                       AS Revenue_Share_Pct,
    ROUND(AVG(t.UnitPrice), 2)                              AS Avg_Unit_Price
FROM transactions t
INNER JOIN products p ON t.ProductID = p.ProductID
GROUP BY p.Category
ORDER BY Total_Revenue DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 04 — Monthly Revenue Trend
-- Concept  : DATE_FORMAT for month grouping, ORDER BY date
-- Purpose  : Track revenue growth month over month (Jan 2024–Dec 2025)
-- ══════════════════════════════════════════════════════════════
SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m')       AS Month_Key,
    DATE_FORMAT(InvoiceDate, '%b-%Y')       AS Month,
    COUNT(DISTINCT InvoiceNo)               AS Total_Orders,
    COUNT(DISTINCT CustomerID)              AS Active_Customers,
    SUM(Quantity)                           AS Total_Items,
    ROUND(SUM(TotalAmount), 2)              AS Total_Revenue,
    ROUND(AVG(TotalAmount), 2)              AS Avg_Bill_Value
FROM transactions
GROUP BY
    DATE_FORMAT(InvoiceDate, '%Y-%m'),
    DATE_FORMAT(InvoiceDate, '%b-%Y')
ORDER BY Month_Key;
-- ══════════════════════════════════════════════════════════════
-- QUERY 05 — Customers Who NEVER Purchased (LEFT JOIN Anti-join)
-- Concept  : LEFT JOIN + IS NULL — classic anti-join pattern
-- Purpose  : Find registered customers with zero transactions
-- ══════════════════════════════════════════════════════════════
SELECT
    c.CustomerID,
    c.CustomerName,
    c.City,
    c.SignupDate,
    c.PilotGroup,
    DATEDIFF(CURDATE(), c.SignupDate)       AS Days_Since_Signup
FROM customers c
LEFT JOIN transactions t ON c.CustomerID = t.CustomerID
WHERE t.CustomerID IS NULL
ORDER BY c.SignupDate DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 06 — Top 10 Customers by Revenue
-- Concept  : INNER JOIN + GROUP BY + ORDER BY DESC + LIMIT
-- Purpose  : Identify Champions — highest value customers
-- ══════════════════════════════════════════════════════════════
SELECT
    t.CustomerID,
    c.CustomerName,
    c.City,
    COUNT(DISTINCT t.InvoiceNo)             AS Total_Orders,
    SUM(t.Quantity)                         AS Total_Items_Bought,
    ROUND(SUM(t.TotalAmount), 2)            AS Total_Revenue,
    ROUND(AVG(t.TotalAmount), 2)            AS Avg_Order_Value,
    DATE(MIN(t.InvoiceDate))                AS First_Purchase,
    DATE(MAX(t.InvoiceDate))                AS Last_Purchase,
    DATEDIFF(MAX(t.InvoiceDate),
             MIN(t.InvoiceDate))            AS Customer_Lifespan_Days
FROM transactions t
INNER JOIN customers c ON t.CustomerID = c.CustomerID
WHERE t.GuestCheckout = 0
GROUP BY t.CustomerID, c.CustomerName, c.City
ORDER BY Total_Revenue DESC
LIMIT 10;
-- ══════════════════════════════════════════════════════════════
-- QUERY 07 — Customer Spending Segments (CASE WHEN)
-- Concept  : CASE WHEN with value ranges, subquery
-- Purpose  : Label every customer as Low/Medium/High/Premium
-- ══════════════════════════════════════════════════════════════
SELECT
    CustomerID,
    CustomerName,
    City,
    Total_Orders,
    ROUND(Total_Revenue, 2)                 AS Total_Revenue,
    CASE
        WHEN Total_Revenue >= 15000         THEN 'Premium'
        WHEN Total_Revenue >= 8000          THEN 'High'
        WHEN Total_Revenue >= 3000          THEN 'Medium'
        ELSE                                     'Low'
    END                                     AS Spending_Segment,
    CASE
        WHEN Total_Orders >= 25             THEN 'Very Frequent'
        WHEN Total_Orders >= 15             THEN 'Frequent'
        WHEN Total_Orders >= 5              THEN 'Regular'
        WHEN Total_Orders >= 2              THEN 'Occasional'
        ELSE                                     'One-time'
    END                                     AS Purchase_Frequency
FROM (
    SELECT
        t.CustomerID,
        c.CustomerName,
        c.City,
        COUNT(DISTINCT t.InvoiceNo)         AS Total_Orders,
        SUM(t.TotalAmount)                  AS Total_Revenue
    FROM transactions t
    INNER JOIN customers c ON t.CustomerID = c.CustomerID
    WHERE t.GuestCheckout = 0
    GROUP BY t.CustomerID, c.CustomerName, c.City
) AS customer_summary
ORDER BY Total_Revenue DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 08 — Segment Summary: How many customers in each group?
-- Concept  : CTE + GROUP BY on CASE column
-- Purpose  : Count customers and revenue per spending segment
-- ══════════════════════════════════════════════════════════════
WITH customer_segments AS (
    SELECT
        t.CustomerID,
        SUM(t.TotalAmount)                  AS Total_Revenue,
        COUNT(DISTINCT t.InvoiceNo)         AS Total_Orders,
        CASE
            WHEN SUM(t.TotalAmount) >= 15000 THEN 'Premium'
            WHEN SUM(t.TotalAmount) >= 8000  THEN 'High'
            WHEN SUM(t.TotalAmount) >= 3000  THEN 'Medium'
            ELSE                                  'Low'
        END                                 AS Segment
    FROM transactions t
    WHERE t.GuestCheckout = 0
    GROUP BY t.CustomerID
)
SELECT
    Segment,
    COUNT(CustomerID)                       AS Customer_Count,
    ROUND(AVG(Total_Revenue), 2)            AS Avg_Revenue,
    ROUND(SUM(Total_Revenue), 2)            AS Total_Segment_Revenue,
    ROUND(SUM(Total_Revenue) /
          SUM(SUM(Total_Revenue)) OVER() * 100, 2)
                                            AS Revenue_Share_Pct,
    ROUND(AVG(Total_Orders), 1)             AS Avg_Orders
FROM customer_segments
GROUP BY Segment
ORDER BY Total_Segment_Revenue DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 09 — RANK Top 10 Customers Per City (Window Function)
-- Concept  : RANK() OVER (PARTITION BY city ORDER BY revenue DESC)
-- Purpose  : Find best customers in each city separately
-- ══════════════════════════════════════════════════════════════
WITH city_revenue AS (
    SELECT
        t.CustomerID,
        c.CustomerName,
        c.City,
        COUNT(DISTINCT t.InvoiceNo)         AS Total_Orders,
        ROUND(SUM(t.TotalAmount), 2)        AS Total_Revenue
    FROM transactions t
    INNER JOIN customers c ON t.CustomerID = c.CustomerID
    WHERE t.GuestCheckout = 0
    GROUP BY t.CustomerID, c.CustomerName, c.City
),
city_ranked AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY City
            ORDER BY Total_Revenue DESC
        )                                   AS City_Rank
    FROM city_revenue
)
SELECT
    City,
    City_Rank,
    CustomerID,
    CustomerName,
    Total_Orders,
    Total_Revenue
FROM city_ranked
WHERE City_Rank <= 10
ORDER BY City, City_Rank;
-- ══════════════════════════════════════════════════════════════
-- QUERY 10 — Days Between Consecutive Purchases (LAG)
-- Concept  : LAG() window function + DATEDIFF
-- Purpose  : Find purchase gap per customer to time campaigns
-- ══════════════════════════════════════════════════════════════
WITH purchase_gaps AS (
    SELECT
        t.CustomerID,
        c.CustomerName,
        c.City,
        DATE(t.InvoiceDate)                 AS Purchase_Date,
        t.InvoiceNo,
        ROUND(t.TotalAmount, 2)             AS Order_Amount,
        LAG(DATE(t.InvoiceDate)) OVER (
            PARTITION BY t.CustomerID
            ORDER BY t.InvoiceDate
        )                                   AS Previous_Purchase_Date
    FROM transactions t
    INNER JOIN customers c ON t.CustomerID = c.CustomerID
    WHERE t.GuestCheckout = 0
)
SELECT
    CustomerID,
    CustomerName,
    City,
    Purchase_Date,
    Previous_Purchase_Date,
    DATEDIFF(
        Purchase_Date,
        Previous_Purchase_Date
    )                                       AS Days_Between_Purchases,
    Order_Amount
FROM purchase_gaps
WHERE Previous_Purchase_Date IS NOT NULL
ORDER BY CustomerID, Purchase_Date;
-- ══════════════════════════════════════════════════════════════
-- QUERY 11 — Average Days Between Purchases Per Customer
-- Concept  : CTE + AVG of DATEDIFF window result
-- Purpose  : Know how often each customer buys → set SMS schedule
-- ══════════════════════════════════════════════════════════════
WITH purchase_gaps AS (
    SELECT
        CustomerID,
        DATE(InvoiceDate)                   AS Purchase_Date,
        LAG(DATE(InvoiceDate)) OVER (
            PARTITION BY CustomerID
            ORDER BY InvoiceDate
        )                                   AS Prev_Purchase_Date
    FROM transactions
    WHERE GuestCheckout = 0
)
SELECT
    g.CustomerID,
    c.CustomerName,
    c.City,
    COUNT(*)                                AS Total_Orders,
    ROUND(AVG(
        DATEDIFF(Purchase_Date, Prev_Purchase_Date)
    ), 1)                                   AS Avg_Days_Between_Purchases,
    MIN(DATEDIFF(
        Purchase_Date, Prev_Purchase_Date)
    )                                       AS Min_Gap_Days,
    MAX(DATEDIFF(
        Purchase_Date, Prev_Purchase_Date)
    )                                       AS Max_Gap_Days
FROM purchase_gaps g
INNER JOIN customers c ON g.CustomerID = c.CustomerID
WHERE Prev_Purchase_Date IS NOT NULL
GROUP BY g.CustomerID, c.CustomerName, c.City
HAVING COUNT(*) >= 3
ORDER BY Avg_Days_Between_Purchases ASC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 12 — Running Total Revenue By Month (SUM OVER)
-- Concept  : Cumulative SUM() OVER (ORDER BY month)
-- Purpose  : Show how revenue accumulates over 24 months
-- ══════════════════════════════════════════════════════════════
WITH monthly_rev AS (
    SELECT
        DATE_FORMAT(InvoiceDate, '%Y-%m')   AS Month_Key,
        DATE_FORMAT(InvoiceDate, '%b-%Y')   AS Month,
        ROUND(SUM(TotalAmount), 2)          AS Monthly_Revenue,
        COUNT(DISTINCT InvoiceNo)           AS Monthly_Orders
    FROM transactions
    GROUP BY
        DATE_FORMAT(InvoiceDate, '%Y-%m'),
        DATE_FORMAT(InvoiceDate, '%b-%Y')
)
SELECT
    Month,
    Monthly_Revenue,
    Monthly_Orders,
    ROUND(SUM(Monthly_Revenue) OVER (
        ORDER BY Month_Key
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2)                                   AS Running_Total_Revenue,
    ROUND(Monthly_Revenue /
          SUM(Monthly_Revenue) OVER() * 100,
    2)                                      AS Month_Revenue_Pct
FROM monthly_rev
ORDER BY Month_Key;
-- ══════════════════════════════════════════════════════════════
-- QUERY 13 — Full RFM Score (Multi-step CTE — Core Query)
-- Concept  : 3-step CTE pipeline + NTILE(5) + CASE WHEN segments
-- Purpose  : Complete customer segmentation — Champions to Lost
-- ══════════════════════════════════════════════════════════════

-- HOW RFM WORKS:
-- R (Recency)   = How recently did they buy? → fewer days = better → score 5
-- F (Frequency) = How many times did they buy? → more = better → score 5
-- M (Monetary)  = How much did they spend total? → more = better → score 5
-- NTILE(5) splits customers into 5 equal buckets (1=worst, 5=best)

WITH rfm_raw AS (
    -- STEP 1: Calculate raw R, F, M values per customer
    SELECT
        t.CustomerID,
        c.CustomerName,
        c.City,
        DATEDIFF(
            (SELECT MAX(InvoiceDate) FROM transactions),
            MAX(t.InvoiceDate)
        )                                   AS Recency_Days,
        COUNT(DISTINCT t.InvoiceNo)         AS Frequency,
        ROUND(SUM(t.TotalAmount), 2)        AS Monetary
    FROM transactions t
    INNER JOIN customers c ON t.CustomerID = c.CustomerID
    WHERE t.GuestCheckout = 0
    GROUP BY t.CustomerID, c.CustomerName, c.City
),
rfm_scored AS (
    -- STEP 2: Convert R, F, M into 1–5 scores using NTILE(5)
    SELECT
        CustomerID,
        CustomerName,
        City,
        Recency_Days,
        Frequency,
        Monetary,
        -- Lower recency days = bought recently = higher score
        NTILE(5) OVER (ORDER BY Recency_Days DESC) AS R_Score,
        -- Higher frequency = better = higher score
        NTILE(5) OVER (ORDER BY Frequency ASC)     AS F_Score,
        -- Higher monetary = better = higher score
        NTILE(5) OVER (ORDER BY Monetary ASC)      AS M_Score
    FROM rfm_raw
),
rfm_segmented AS (
    -- STEP 3: Combine scores and label segment
    SELECT
        CustomerID,
        CustomerName,
        City,
        Recency_Days,
        Frequency,
        Monetary,
        R_Score,
        F_Score,
        M_Score,
        CONCAT(R_Score, F_Score, M_Score)   AS RFM_Code,
        ROUND((R_Score + F_Score + M_Score) / 3.0, 2)
                                            AS RFM_Avg,
        CASE
            WHEN R_Score >= 4 AND F_Score >= 4 AND M_Score >= 4
                THEN 'Champions'
            WHEN R_Score >= 3 AND F_Score >= 3 AND M_Score >= 3
                THEN 'Loyal Customers'
            WHEN R_Score >= 4 AND F_Score <= 2
                THEN 'New Customers'
            WHEN R_Score >= 3 AND M_Score >= 4
                THEN 'Potential Loyalists'
            WHEN R_Score <= 2 AND F_Score >= 4 AND M_Score >= 4
                THEN 'Cannot Lose Them'
            WHEN R_Score <= 2 AND F_Score >= 3 AND M_Score >= 3
                THEN 'At Risk'
            WHEN R_Score <= 2 AND F_Score <= 2 AND M_Score <= 2
                THEN 'Lost'
            ELSE
                'Hibernating'
        END                                 AS RFM_Segment
    FROM rfm_scored
)
-- Final output: every customer with full RFM profile
SELECT
    CustomerID,
    CustomerName,
    City,
    Recency_Days,
    Frequency,
    Monetary,
    R_Score,
    F_Score,
    M_Score,
    RFM_Code,
    RFM_Avg,
    RFM_Segment
FROM rfm_segmented
ORDER BY Monetary DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 14 — RFM Segment Summary (How many customers per segment)
-- Concept  : Reuse CTE logic + GROUP BY on segment
-- Purpose  : Dashboard KPI — which segment has most value?
-- ══════════════════════════════════════════════════════════════
WITH rfm_raw AS (
    SELECT
        t.CustomerID,
        DATEDIFF(
            (SELECT MAX(InvoiceDate) FROM transactions),
            MAX(t.InvoiceDate))             AS Recency_Days,
        COUNT(DISTINCT t.InvoiceNo)         AS Frequency,
        ROUND(SUM(t.TotalAmount), 2)        AS Monetary
    FROM transactions t
    WHERE t.GuestCheckout = 0
    GROUP BY t.CustomerID
),
rfm_scored AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY Recency_Days DESC) AS R_Score,
        NTILE(5) OVER (ORDER BY Frequency ASC)     AS F_Score,
        NTILE(5) OVER (ORDER BY Monetary ASC)      AS M_Score
    FROM rfm_raw
),
rfm_labeled AS (
    SELECT *,
        CASE
            WHEN R_Score>=4 AND F_Score>=4 AND M_Score>=4  THEN 'Champions'
            WHEN R_Score>=3 AND F_Score>=3 AND M_Score>=3  THEN 'Loyal Customers'
            WHEN R_Score>=4 AND F_Score<=2                 THEN 'New Customers'
            WHEN R_Score>=3 AND M_Score>=4                 THEN 'Potential Loyalists'
            WHEN R_Score<=2 AND F_Score>=4 AND M_Score>=4  THEN 'Cannot Lose Them'
            WHEN R_Score<=2 AND F_Score>=3 AND M_Score>=3  THEN 'At Risk'
            WHEN R_Score<=2 AND F_Score<=2 AND M_Score<=2  THEN 'Lost'
            ELSE                                                'Hibernating'
        END                                 AS RFM_Segment
    FROM rfm_scored
)
SELECT
    RFM_Segment,
    COUNT(CustomerID)                       AS Customer_Count,
    ROUND(AVG(Recency_Days), 1)             AS Avg_Recency_Days,
    ROUND(AVG(Frequency), 1)                AS Avg_Orders,
    ROUND(AVG(Monetary), 2)                 AS Avg_Revenue,
    ROUND(SUM(Monetary), 2)                 AS Total_Revenue,
    ROUND(SUM(Monetary) /
          SUM(SUM(Monetary)) OVER() * 100, 2)
                                            AS Revenue_Share_Pct
FROM rfm_labeled
GROUP BY RFM_Segment
ORDER BY Total_Revenue DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 15 — A/B Test: Targeted vs Generic Campaign
-- Concept  : JOIN + GROUP BY PilotGroup + response rate calc
-- Purpose  : Prove targeted campaigns work better than mass SMS
-- ══════════════════════════════════════════════════════════════
SELECT
    c.PilotGroup,
    COUNT(DISTINCT c.CustomerID)            AS Total_Customers,
    SUM(c.Responded)                        AS Total_Responded,
    ROUND(
        SUM(c.Responded) /
        COUNT(DISTINCT c.CustomerID) * 100,
    2)                                      AS Response_Rate_Pct,
    COUNT(DISTINCT t.InvoiceNo)             AS Post_Campaign_Orders,
    ROUND(SUM(t.TotalAmount), 2)            AS Post_Campaign_Revenue,
    ROUND(AVG(t.TotalAmount), 2)            AS Avg_Order_Value
FROM customers c
LEFT JOIN transactions t
    ON  c.CustomerID = t.CustomerID
    AND t.InvoiceDate >= '2024-06-01'       -- post-campaign period
WHERE c.PilotGroup IN ('Targeted', 'Generic')
GROUP BY c.PilotGroup
ORDER BY Response_Rate_Pct DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 16 — Top 10 Products by Revenue (RANK window)
-- Concept  : JOIN + GROUP BY + RANK() window function
-- Purpose  : Find bestselling products + price realisation
-- ══════════════════════════════════════════════════════════════
SELECT
    p.ProductID,
    p.ProductName,
    p.Category,
    p.MRP,
    SUM(t.Quantity)                         AS Total_Qty_Sold,
    COUNT(DISTINCT t.InvoiceNo)             AS Total_Orders,
    ROUND(SUM(t.TotalAmount), 2)            AS Total_Revenue,
    ROUND(AVG(t.UnitPrice), 2)              AS Avg_Selling_Price,
    ROUND(AVG(t.UnitPrice) / p.MRP * 100, 1)
                                            AS Price_Realization_Pct,
    RANK() OVER (
        ORDER BY SUM(t.TotalAmount) DESC
    )                                       AS Revenue_Rank
FROM transactions t
INNER JOIN products p ON t.ProductID = p.ProductID
GROUP BY p.ProductID, p.ProductName, p.Category, p.MRP
ORDER BY Total_Revenue DESC
LIMIT 10;
-- ══════════════════════════════════════════════════════════════
-- QUERY 17 — Store/Channel Performance
-- Concept  : GROUP BY Store + window function % share
-- Purpose  : Compare APP (online) vs physical stores
-- ══════════════════════════════════════════════════════════════
SELECT
    Store                                   AS Channel,
    COUNT(DISTINCT InvoiceNo)               AS Total_Orders,
    COUNT(DISTINCT CustomerID)              AS Unique_Customers,
    SUM(Quantity)                           AS Total_Items,
    ROUND(SUM(TotalAmount), 2)              AS Total_Revenue,
    ROUND(AVG(TotalAmount), 2)              AS Avg_Order_Value,
    ROUND(SUM(TotalAmount) /
          SUM(SUM(TotalAmount)) OVER() * 100, 2)
                                            AS Revenue_Share_Pct
FROM transactions
WHERE GuestCheckout = 0
GROUP BY Store
ORDER BY Total_Revenue DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 18 — Weekend vs Weekday Sales
-- Concept  : DAYOFWEEK() + CASE + GROUP BY
-- Purpose  : Find peak sales days to time promotional messages
-- ══════════════════════════════════════════════════════════════
SELECT
    CASE
        WHEN DAYOFWEEK(InvoiceDate) IN (1, 7)
        THEN 'Weekend'
        ELSE 'Weekday'
    END                                     AS Day_Type,
    DAYNAME(InvoiceDate)                    AS Day_Name,
    COUNT(DISTINCT InvoiceNo)               AS Total_Orders,
    ROUND(SUM(TotalAmount), 2)              AS Total_Revenue,
    ROUND(AVG(TotalAmount), 2)              AS Avg_Order_Value
FROM transactions
GROUP BY Day_Type, DAYNAME(InvoiceDate)
ORDER BY Day_Type, Total_Revenue DESC;
-- ══════════════════════════════════════════════════════════════
-- QUERY 19 — Customer Retention: Repeat vs One-time Buyers
-- Concept  : Subquery + CASE + COUNT + window % share
-- Purpose  : Diagnose retention problem — what % buy only once?
-- ══════════════════════════════════════════════════════════════
SELECT
    Buyer_Type,
    COUNT(CustomerID)                       AS Customer_Count,
    ROUND(
        COUNT(CustomerID) /
        SUM(COUNT(CustomerID)) OVER() * 100,
    2)                                      AS Pct_of_Customers
FROM (
    SELECT
        CustomerID,
        CASE
            WHEN COUNT(DISTINCT InvoiceNo) = 1     THEN 'One-time Buyer'
            WHEN COUNT(DISTINCT InvoiceNo) BETWEEN 2 AND 5
                                                   THEN 'Occasional (2–5)'
            WHEN COUNT(DISTINCT InvoiceNo) BETWEEN 6 AND 15
                                                   THEN 'Regular (6–15)'
            ELSE                                        'Frequent (16+)'
        END                                 AS Buyer_Type
    FROM transactions
    WHERE GuestCheckout = 0
    GROUP BY CustomerID
) AS buyer_summary
GROUP BY Buyer_Type
ORDER BY Customer_Count DESC;








