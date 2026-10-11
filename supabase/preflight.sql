-- Read-only inventory to save before applying the operational migration.
-- Save results with the project backup; this file does not change permissions.
select table_name,column_name,data_type,is_nullable,column_default
from information_schema.columns where table_schema='public'
and table_name in ('products','sales','sale_items') order by table_name,ordinal_position;

select p.proname,pg_get_functiondef(p.oid) definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('complete_sale','complete_named_sale','mark_order_served','list_service_orders');

select * from pg_policies where schemaname='public' and tablename in ('products','sales','sale_items');
select * from information_schema.role_table_grants where table_schema='public' and table_name in ('products','sales','sale_items');
select count(*) products, count(*) filter(where price<0 or stock<0) invalid_products from public.products;
select count(*) sales, coalesce(sum(total),0) historical_total from public.sales;
select count(*) sale_lines, count(*) filter(where qty<=0) invalid_quantities from public.sale_items;
