use marketplace_db;

/*-------------------------------Vw_order_summary_table----------------------------------------*/
CREATE OR REPLACE VIEW vw_order_summary AS
SELECT
    o.order_id,
    o.customer_id,
    o.product_id,
    p.category,
    p.brand,
    p.sub_category,
    o.order_date,
    o.quantity,
    o.order_status,
    o.order_channel,
    o.warehouse_id,
    o.payment_method,
    -- Revenue
    (o.quantity * p.mrp)                                              AS gross_revenue,
    -- Product Cost
    (o.quantity * p.cost_price)                                       AS total_cost,
    -- Discount
    COALESCE(d.discount_amount, 0)                                    AS discount_amount,
    -- Net Revenue
    (o.quantity * p.mrp) - COALESCE(d.discount_amount, 0)            AS net_revenue,
    -- Logistics
    COALESCE(lc.shipping_cost, 0)                                     AS shipping_cost,
    COALESCE(lc.reverse_shipping_cost, 0)                             AS reverse_shipping_cost,
    COALESCE(lc.shipping_cost, 0)
        + COALESCE(lc.reverse_shipping_cost, 0)                      AS total_logistics,
    -- ✅ COALESCE fixes NULL delivery_days → default 6
    COALESCE(lc.delivery_days, 6)                                     AS delivery_days,
    -- ✅ COALESCE fixes NULL delivery_status → default ON_TIME
    COALESCE(lc.delivery_status, 'ON_TIME')                          AS delivery_status,
    -- Payment Fee
    COALESCE(
        ROUND((o.quantity * p.mrp) * pf.fee_percentage / 100, 2)
    , 0)                                                              AS payment_fee,
    -- Return Info
    CASE WHEN r.return_id IS NOT NULL THEN 1 ELSE 0 END              AS is_returned,
    COALESCE(r.return_reason, 'No Return')                           AS return_reason,
    COALESCE(r.refund_status, 'NA')                                  AS refund_status,
    -- Net Profit
    CASE
        WHEN r.return_id IS NOT NULL THEN
            0
            - (o.quantity * p.cost_price)
            - COALESCE(lc.shipping_cost, 0)
            - COALESCE(lc.reverse_shipping_cost, 0)
            - COALESCE(
                ROUND((o.quantity * p.mrp) * pf.fee_percentage / 100, 2)
              , 0)
        ELSE
            (o.quantity * p.mrp)
            - COALESCE(d.discount_amount, 0)
            - (o.quantity * p.cost_price)
            - COALESCE(lc.shipping_cost, 0)
            - COALESCE(lc.reverse_shipping_cost, 0)
            - COALESCE(
                ROUND((o.quantity * p.mrp) * pf.fee_percentage / 100, 2)
              , 0)
    END                                                               AS net_profit
FROM orders o
JOIN      products        p   ON o.product_id     = p.product_id
LEFT JOIN discounts       d   ON o.order_id       = d.order_id
LEFT JOIN returns         r   ON o.order_id       = r.order_id
LEFT JOIN logistics_cost  lc  ON o.order_id       = lc.order_id
LEFT JOIN payment_fees    pf  ON o.payment_method = pf.payment_method;
/*-------------------------------Vw_order_summary_table----------------------------------------*/

select * from vw_order_summary limit 10;

/*--Task 1 — Revenue vs Profit Reality--*/
SELECT
    COUNT(order_id)                                                    AS total_orders,
    SUM(gross_revenue)                                                 AS total_gross_revenue,
    SUM(discount_amount)                                               AS total_discounts,
    SUM(total_cost)                                                    AS total_product_cost,
    SUM(CASE WHEN is_returned=1 THEN gross_revenue ELSE 0 END)         AS total_return_loss,
    SUM(total_logistics)                                               AS total_logistics_cost,
    SUM(payment_fee)                                                   AS total_payment_fees,
    SUM(net_profit)                                                    AS total_net_profit,
    ROUND(SUM(net_profit)*100.0/SUM(gross_revenue),2)                  AS profit_margin_pct
FROM vw_order_summary;
/*___________Task 1 — Revenue vs Profit Reality_____________________________*/

/*-----------Task 2 — Category-wise Sales & Profit-----------------------------------*/

SELECT
    category,
    COUNT(order_id)                                                    AS total_orders,
    SUM(gross_revenue)                                                 AS total_revenue,
    SUM(net_profit)                                                    AS total_net_profit,
    ROUND(SUM(net_profit)*100.0/SUM(gross_revenue),2)                  AS profit_margin_pct,
    ROUND(SUM(is_returned)*100.0/COUNT(order_id),2)                    AS return_rate_pct
FROM vw_order_summary
GROUP BY category
ORDER BY total_net_profit DESC;
/*__________________Task 2 — Category-wise Sales & Profit______________________*/

/*___________Task 3 — Loss-Making Products_____________________________*/
SELECT
    product_id,
    category,
    COUNT(order_id)                                                    AS total_orders,
    SUM(gross_revenue)                                                 AS total_revenue,
    SUM(net_profit)                                                    AS total_net_profit,
    ROUND(SUM(net_profit)*100.0/SUM(gross_revenue),2)                  AS profit_margin_pct,
    ROUND(SUM(is_returned)*100.0/COUNT(order_id),2)                    AS return_rate_pct
FROM vw_order_summary
GROUP BY product_id, category
HAVING SUM(net_profit) < 0
ORDER BY total_net_profit ASC;
/*_____________Task 3 — Loss-Making Products___________________________*/

/*____________Task 4 — Discount Usage Overview____________________________*/

SELECT
    COUNT(order_id)                                                    AS total_orders,
    SUM(CASE WHEN discount_amount>0 THEN 1 ELSE 0 END)                 AS discounted_orders,
    ROUND(SUM(CASE WHEN discount_amount>0 THEN 1 ELSE 0 END)
          *100.0/COUNT(order_id),2)                                    AS disc_usage_pct,
    SUM(discount_amount)                                               AS total_discount_amount,
    ROUND(AVG(CASE WHEN discount_amount>0
                   THEN discount_amount END),2)                        AS avg_disc_per_disc_order,
    MAX(discount_amount)                                               AS max_discount
FROM vw_order_summary;
/*_________________Task 4 — Discount Usage Overview_______________________*/

/*_____________Task 5 — Payment Method Popularity___________________________*/
SELECT
    payment_method,
    COUNT(order_id)                                                    AS total_orders,
    ROUND(COUNT(order_id)*100.0/SUM(COUNT(order_id)) OVER(),2)         AS order_share_pct,
    SUM(gross_revenue)                                                 AS total_revenue,
    SUM(payment_fee)                                                   AS total_fees_paid,
    ROUND(SUM(payment_fee)*100.0/SUM(gross_revenue),2)                 AS fee_pct_of_revenue,
    ROUND(SUM(net_profit)*100.0/SUM(gross_revenue),2)                  AS profit_margin_pct,
    ROUND(SUM(is_returned)*100.0/COUNT(order_id),2)                    AS return_rate_pct
FROM vw_order_summary
GROUP BY payment_method
ORDER BY total_revenue DESC;
/*___________Task 5 — Payment Method Popularity_____________________________*/

/*_____________Task 6 — Discount vs Profit Gap___________________________*/

SELECT
    CASE WHEN discount_amount>0 THEN 'Discounted'
         ELSE 'Non-Discounted' END                                     AS order_type,
    COUNT(order_id)                                                    AS total_orders,
    ROUND(AVG(discount_amount),2)                                      AS avg_discount,
    ROUND(AVG(net_profit),2)                                           AS avg_profit_per_order,
    ROUND(SUM(net_profit)*100.0/SUM(gross_revenue),2)                  AS profit_margin_pct,
    ROUND(SUM(is_returned)*100.0/COUNT(order_id),2)                    AS return_rate_pct
FROM vw_order_summary
GROUP BY CASE WHEN discount_amount>0
              THEN 'Discounted'
              ELSE 'Non-Discounted' END;
/*________________Task 6 — Discount vs Profit Gap________________________*/

/*___________Task 7 — Return Impact on Revenue_____________________________*/
SELECT
    COUNT(order_id)                                                    AS total_returned_orders,
    ROUND(COUNT(order_id)*100.0/SUM(COUNT(order_id)) OVER(),2)         AS return_rate_pct,
    SUM(gross_revenue)                                                 AS revenue_reversed,
    SUM(total_cost)                                                    AS product_cost_incurred,
    SUM(total_logistics)                                               AS logistics_wasted,
    SUM(payment_fee)                                                   AS fees_lost,
    ABS(SUM(net_profit))                                               AS total_financial_loss,
    ROUND(ABS(AVG(net_profit)),2)                                      AS avg_loss_per_return
FROM vw_order_summary
WHERE is_returned = 1;
/*_____________Task 7 — Return Impact on Revenue___________________________*/

/*____________Task 8 — Return Reason Analysis____________________________*/
SELECT
    return_reason,
    COUNT(order_id)                                                    AS total_returns,
    ROUND(COUNT(order_id)*100.0/SUM(COUNT(order_id)) OVER(),2)         AS return_share_pct,
    SUM(gross_revenue)                                                 AS revenue_lost,
    ABS(SUM(net_profit))                                               AS total_financial_loss,
    ROUND(ABS(AVG(net_profit)),2)                                      AS avg_loss_per_return
FROM vw_order_summary
WHERE is_returned = 1
GROUP BY return_reason
ORDER BY total_financial_loss DESC;
/*________________Task 8 — Return Reason Analysis________________________*/

/*____________Task 9 — Logistics Cost Burden____________________________*/
SELECT
    order_id,
    category,
    gross_revenue,
    total_logistics,
    ROUND(total_logistics*100.0/NULLIF(gross_revenue,0),2)             AS logistics_pct,
    net_profit,
    CASE WHEN net_profit<0 THEN 'LOSS' ELSE 'PROFIT' END               AS status
FROM vw_order_summary
WHERE total_logistics > gross_revenue * 0.20
ORDER BY logistics_pct DESC;
/*______________Task 9 — Logistics Cost Burden__________________________*/

/*_____________Task 10 — Payment Fee Leakage___________________________*/

SELECT
    payment_method,
    SUM(payment_fee)                                                   AS total_fees_paid,
    ROUND(SUM(payment_fee)*100.0/SUM(SUM(payment_fee)) OVER(),2)       AS fee_share_pct,
    ROUND(AVG(payment_fee),2)                                          AS avg_fee_per_order,
    ROUND(SUM(payment_fee)*100.0/SUM(gross_revenue),2)                 AS fee_pct_of_revenue,
    ROUND(SUM(net_profit)*100.0/SUM(gross_revenue),2)                  AS profit_margin_pct
FROM vw_order_summary
GROUP BY payment_method
ORDER BY total_fees_paid DESC;
/*______________Task 10 — Payment Fee Leakage__________________________*/

/*______________Task 11 — Revenue Leakage Breakdown__________________________*/

SELECT
    'Return Losses'  AS leakage_source,
    SUM(CASE WHEN is_returned=1 THEN gross_revenue ELSE 0 END)         AS total_leakage,
    ROUND(SUM(CASE WHEN is_returned=1 THEN gross_revenue ELSE 0 END)
          *100.0/SUM(gross_revenue),2)                                 AS leakage_pct
FROM vw_order_summary
UNION ALL
SELECT 'Discounts', SUM(discount_amount),
    ROUND(SUM(discount_amount)*100.0/SUM(gross_revenue),2)
FROM vw_order_summary
UNION ALL
SELECT 'Payment Fees', SUM(payment_fee),
    ROUND(SUM(payment_fee)*100.0/SUM(gross_revenue),2)
FROM vw_order_summary
UNION ALL
SELECT 'Logistics Cost', SUM(total_logistics),
    ROUND(SUM(total_logistics)*100.0/SUM(gross_revenue),2)
FROM vw_order_summary
ORDER BY total_leakage DESC;
/*____________Task 11 — Revenue Leakage Breakdown____________________________*/

/*____________Task 12 — Product Profit Ranking____________________________*/
SELECT
    product_id,
    category,
    COUNT(order_id)                                                    AS total_orders,
    SUM(net_profit)                                                    AS total_net_profit,
    ROUND(SUM(net_profit)*100.0/SUM(gross_revenue),2)                  AS profit_margin_pct,
    ROUND(SUM(is_returned)*100.0/COUNT(order_id),2)                    AS return_rate_pct,
    RANK() OVER (ORDER BY SUM(net_profit) DESC)                        AS overall_rank,
    RANK() OVER (PARTITION BY category
                 ORDER BY SUM(net_profit) DESC)                        AS rank_in_category
FROM vw_order_summary
GROUP BY product_id, category
ORDER BY overall_rank;
/*___________Task 12 — Product Profit Ranking_____________________________*/

/*__________Task 13 — Category Margin Stability______________________________*/

WITH order_margins AS (
    SELECT category,
           ROUND(net_profit*100.0/NULLIF(gross_revenue,0),2) AS order_margin_pct
    FROM vw_order_summary
)
SELECT
    category,
    ROUND(AVG(order_margin_pct),2)                                     AS avg_margin_pct,
    ROUND(STDDEV(order_margin_pct),2)                                  AS margin_std_dev,
    ROUND(MIN(order_margin_pct),2)                                     AS min_margin,
    ROUND(MAX(order_margin_pct),2)                                     AS max_margin,
    RANK() OVER (ORDER BY STDDEV(order_margin_pct) DESC)               AS volatility_rank
FROM order_margins
GROUP BY category
ORDER BY volatility_rank;
/*________________Task 13 — Category Margin Stability__________________________*/

/*______________Task 14 — High-Risk Customers__________________________*/

WITH customer_stats AS (
    SELECT
        customer_id,
        COUNT(order_id)                                                AS total_orders,
        SUM(is_returned)                                               AS total_returns,
        ROUND(SUM(is_returned)*100.0/COUNT(order_id),2)               AS return_rate_pct,
        SUM(net_profit)                                                AS total_profit
    FROM vw_order_summary
    GROUP BY customer_id
)
SELECT
    customer_id,
    total_orders,
    total_returns,
    return_rate_pct,
    total_profit,
    CASE
        WHEN return_rate_pct >= 35.28 THEN 'HIGH RISK'
        WHEN return_rate_pct >  17.64 THEN 'ABOVE AVERAGE'
        WHEN return_rate_pct =  0     THEN 'ZERO RETURNS'
        ELSE                               'NORMAL'
    END                                                                AS risk_flag
FROM customer_stats
ORDER BY return_rate_pct DESC, total_orders DESC;
/*________________Task 14 — High-Risk Customers_________________________*/

/*_______________Task 15 — Executive Profitability Summary_________________________*/

SELECT
    SUM(gross_revenue)                                                 AS total_gross_revenue,
    SUM(discount_amount)                                               AS total_discounts,
    SUM(total_cost)                                                    AS total_product_cost,
    SUM(CASE WHEN is_returned=1 THEN gross_revenue ELSE 0 END)         AS total_return_loss,
    SUM(total_logistics)                                               AS total_logistics_cost,
    SUM(payment_fee)                                                   AS total_payment_fees,
    SUM(net_profit)                                                    AS total_net_profit,
    ROUND(SUM(net_profit)*100.0/SUM(gross_revenue),2)                  AS net_profit_margin_pct,
    -- Recovery scenario: fix returns 50%
    ROUND((SUM(net_profit)+SUM(CASE WHEN is_returned=1
           THEN gross_revenue*0.5 ELSE 0 END))
           *100.0/SUM(gross_revenue),2)                                AS margin_if_returns_halved,
    -- Recovery scenario: fix returns + discounts
    ROUND((SUM(net_profit)+SUM(CASE WHEN is_returned=1
           THEN gross_revenue*0.5 ELSE 0 END)+SUM(discount_amount*0.4))
           *100.0/SUM(gross_revenue),2)                                AS margin_if_both_fixed
FROM vw_order_summary;
/*_________________Task 15 — Executive Profitability Summary_______________________*/