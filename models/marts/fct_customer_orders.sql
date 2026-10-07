with
-- import CTEs
payment as(
    select *
    from {{ source('stripe', 'payment') }}
),
orders as(
    select *
    from {{ source('jaffle_shop', 'orders') }}
),
customers as(
    select *
    from {{ source('jaffle_shop', 'customers') }}
),
-- Logical CTEs
-- Final CTE
-- Simple Select Statment
p as (
    select 
        orderid as order_id, 
        max(created) as payment_finalized_date, 
        sum(amount) / 100.0 as total_amount_paid 
    from payments
    where status <> 'fail'
    group by 1
),
x as(
    select
        p.order_id,
        sum(t2.total_amount_paid) as clv_bad
        from paid_orders p
        left join paid_orders t2 
            on p.customer_id = t2.customer_id
            and p.order_id >= t2.order_id --This is to determine the customer lifetime value for each order--
        group by 1
        order by p.order_id
),
paid_orders as (
    select 
        orders.id as order_id,
        orders.user_id as customer_id,
        orders.order_date as order_placed_at,
        orders.status as order_status,
        p.total_amount_paid,
        p.payment_finalized_date,
        customers.first_name as customer_first_name,
        customers.last_name as customer_last_name
    from orders
    left join p 
        on orders.id = p.order_id
    left join customers
        on orders.user_id = customers.id 
),
customer_orders as (
    select 
        customers.id as customer_id,
        min(orders.order_date) as first_order_date,
        max(orders.order_date) as most_recent_order_date,
        count(orders.id) as number_of_orders
    from customers
    left join orders
    on orders.user_id = customers.id 
    group by 1
),

final as (
    select
        paid_orders.*,
        row_number() over (
            order by paid_orders.order_id) as transaction_seq, --This is to determine the sequence of transactions--
        row_number() over (
            partition by customer_id 
            order by paid_orders.order_id) as customer_sales_seq, --This is to determine the sequence of sales for each customer--
        case 
            when (
                rank() over (
                    partition by customer_id 
                    order by order_placed_at, paid_orders.order_id
                    ) = 1
            )then 'new'
        else 'return' end as nvsr, --This is to determine if the order is a new or returning customer--
        x.clv_bad as customer_lifetime_value,
        customer_orders.first_order_date as fdos --This is to determine the first date of sale for each customer--
    from paid_orders
    left join customer_orders 
        using (customer_id)
    left outer join x 
        on x.order_id = p.order_id
    order by order_id
)
select * from final