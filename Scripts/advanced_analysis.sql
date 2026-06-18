/*Change Over time analysis: 
Analyse how a measure evolves over time, 
helps track trends and identify seasonality in our data
*/

--Analyse sales performance over time
SELECT 
YEAR(order_date) order_year,
SUM(sale_amount) total_sale,
COUNT(DISTINCT customer_key) total_customers,
SUM(quantity) total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date);

SELECT 
MONTH(order_date) order_month,
SUM(sale_amount) total_sale,
COUNT(DISTINCT customer_key) total_customers,
SUM(quantity) total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY MONTH(order_date)
ORDER BY MONTH(order_date);

SELECT 
YEAR(order_date) order_year,
MONTH(order_date) order_month,
SUM(sale_amount) total_sale,
COUNT(DISTINCT customer_key) total_customers,
SUM(quantity) total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date),MONTH(order_date)
ORDER BY YEAR(order_date),MONTH(order_date);

/*Cumulative analysis:
Aggregate the data progressively overtime
Helps to understand whether our business is growing or declining
*/

--Calculate the total sales per month
--and the running total of sales over time
SELECT 
order_date,
total_sale,
SUM(total_sale) OVER(PARTITION BY year(ORDER_DATE) order by order_date) running_sale,
AVG(avg_price) OVER(ORDER BY order_date) moving_avg
FROM(
SELECT
DATETRUNC(month, order_date) order_date,
SUM(sale_amount) total_sale,
AVG(price) avg_price
FROM gold.fact_sales
WHERE DATETRUNC(month, order_date) IS NOT NULL
GROUP BY DATETRUNC(month, order_date))t

/*
Performance Analysis:
Comparing the current value to a target value.
helps to measure success and comapre performance
*/
--Analyse the yearly performance of products by comparing each product's
--sales to both its average sales performance and the previous year's sales.
WITH yearly_sale AS(
    SELECT 
YEAR(s.order_date) order_year,
p.product_name,
SUM(s.sale_amount) current_sales
FROM gold.fact_sales s
LEFT JOIN gold.dim_products p
ON s.product_key=p.product_key
WHERE s.order_date IS NOT NULL
GROUP BY YEAR(s.order_date),
p.product_name
)


SELECT order_year,
product_name,
current_sales,
AVG(current_sales) OVER(PARTITION BY product_name) avg_sales,
current_sales-AVG(current_sales) OVER(PARTITION BY product_name) diff_avg,
CASE WHEN current_sales>AVG(current_sales) OVER(PARTITION BY product_name) THEN 'above average'
WHEN current_sales<AVG(current_sales) OVER(PARTITION BY product_name) THEN 'below average'
ELSE 'average'
END AS avg_flag,
LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) previous_yr_sales,
current_sales-LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) diff_py,
CASE 
WHEN current_sales>LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) 
THEN 'Increase'
WHEN current_sales<LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) 
THEN 'Decrease'
ELSE 'No Change'
END AS py_flag
FROM yearly_sale
GO

/*
Part-to-Whole Analysis:
Analyse how an individual part is performing compared to the overall, allowing us to
understand which category has the greatest impact on the business
*/

--Which categories contribute the most to overall sales
WITH cat_sales AS (
SELECT 
p.category,
SUM(s.sale_amount) total_sale_per_category
FROM gold.fact_sales s
LEFT JOIN gold.dim_products p
ON s.product_key=p.product_key
GROUP BY p.category
)
SELECT 
category,
total_sale_per_category,
SUM(total_sale_per_category) OVER() overall_sales,
ROUND((CAST(total_sale_per_category as fLOAT)/SUM(total_sale_per_category) OVER())*100,2) contribution
FROM cat_sales
ORDER BY contribution DESC


/* Data segmentation:
Group the data based on a specific range.
Helps understand the corelation between two measures.
*/
GO

-- Segment products into cost ranges and count hom many products sall into each segment
WITH cte_cost_range AS 
(
    SELECT
CASE WHEN product_cost<100 THEN 'Below 100'
WHEN product_cost>100 AND product_cost<500 THEN 'Above 100 AND Below 500'
WHEN product_cost>500 AND product_cost<1000 THEN 'Above 500 AND Below 1000'
WHEN product_cost>1000 AND product_cost<2000 THEN 'Above 1000 AND Below 2000'
ELSE 'Above 2000'
END AS cost_range,
product_key,
product_name,
product_cost
FROM gold.dim_products
)

--Total Revenue from each cost range
SELECT 
cr.cost_range,
COUNT(*) total_products,
COALESCE(SUM(s.sale_amount),0) total_revune
FROM cte_cost_range cr
LEFT JOIN gold.fact_sales s
ON cr.product_key = s.product_key
GROUP BY cost_range
ORDER BY total_revune DESC;
--Highest Reveune from products above 1000 and below 2000


--Group customers into three segments based on their spending behaviour
--VIP: at least 12 months of history and spending more than 5k
--Regular: at least 12 months of history but spending 5k or less
--new:lifespace less than 12 months
WITH customer_lifespan as (
    SELECT 
c.customer_key,
SUM(f.sale_amount) as total_spending,
MIN(order_date) AS first_order,
MAX(order_date) AS last_order,
DATEDIFF(month,MIN(order_date),MAX(order_date)) life_span
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON f.customer_key = c.customer_key
GROUP by 
c.customer_key),

customer_groups AS(
    
SELECT
customer_key,
life_span,
total_spending,
CASE WHEN life_span>=12 AND total_spending>5000 THEN 'VIP'
WHEN life_span>=12 AND total_spending<5000 THEN 'Regular'
ELSE 'New'
END customer_group
FROM customer_lifespan)

SELECT 
customer_group,
COUNT(*) total_customers
FROM customer_groups
GROUP by customer_group
ORDER BY total_customers DESC
