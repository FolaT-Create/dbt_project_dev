--import ctes
select 
    id as order_id,
    user_id as customer_id,
    order_date as order_placed_at,
    status as order_status
from {{ source('jaffle_shop', 'orders') }} as orders

select 
    orderid as order_id,
    max(created) as payment_finalized_date,
    sum(amount) / 100.0 as total_amount_paid
from {{ source('stripe', 'payment') }} as payments
where status <> 'fail'
group by 1

select *
from {{ source('jaffle_shop', 'customers') }} as customers

--logical ctes

with paid_orders as (
    select 
        orders *,
        p.total_amount_paid,
        p.payment_finalized_date,
        c.first_name as customer_first_name,
        c.last_name as customer_last_name
    from orders
    left join payments p
        on orders.order_id = p.order_id
    left join customers c
        on orders.customer_id = c.id
),

customer_orders as (
    select 
        c.id as customer_id,
        min(o.order_date) as first_order_date,
        max(o.order_date) as most_recent_order_date,
        count(o.id) as number_of_orders
    from customers c 
    left join orders o
        on o.user_id = c.id 
    group by 1
),

x as (
    select
        p.order_id,
        sum(t2.total_amount_paid) as clv_bad
    from paid_orders p
    left join paid_orders t2 
        on p.customer_id = t2.customer_id 
        and p.order_id >= t2.order_id
    group by 1
    order by p.order_id  
),

-- main final ctes

select
    p.*,
    row_number() 
        over (
            order by p.order_id) as transaction_seq,
    row_number() 
        over (
            partition by customer_id 
            order by p.order_id) as customer_sales_seq,
    case 
        when c.first_order_date = p.order_placed_at
            then 'new'
            else 'return' 
        end as nvsr,
    x.clv_bad as customer_lifetime_value,
    c.first_order_date as fdos
from paid_orders p
left join customer_orders as c 
    using (customer_id)
left outer join x 
    on x.order_id = p.order_id
order by order_id
