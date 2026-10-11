-- Run in Supabase SQL Editor. Existing complete_sale remains unchanged.
-- Requires existing sales(id, created_at), sale_items(sale_id, product_name, qty).
begin;
do $$ begin
  if to_regclass('public.pos_config') is not null then
    raise exception 'Operational POS is installed. Do not rerun the legacy order-tracking script. See supabase/SETUP.md.';
  end if;
end $$;
alter table public.sales add column if not exists service_status text;
alter table public.sales add column if not exists served_at timestamptz;
alter table public.sales add column if not exists served_by uuid;
alter table public.sales add column if not exists customer_name text;
-- Only future sales become pending; historical service status is unknown.
alter table public.sales alter column service_status set default 'pending';

-- Block direct status edits, even if an existing sales UPDATE policy is broad.
create or replace function public.guard_service_status() returns trigger
language plpgsql set search_path = '' as $$
begin
  if TG_OP = 'INSERT' then
    new.service_status := 'pending';
    new.served_at := null;
    new.served_by := null;
    new.customer_name := coalesce(nullif(current_setting('hankatsu.customer_name', true), ''), new.customer_name);
  elsif (new.service_status, new.served_at, new.served_by) is distinct from
        (old.service_status, old.served_at, old.served_by) then
    if coalesce(auth.jwt()->'app_metadata'->>'role', '') <> 'admin' then
      raise exception 'Administrator access required';
    end if;
    if old.service_status is distinct from 'pending' or new.service_status is distinct from 'served' then
      raise exception 'Only waiting orders can be marked served';
    end if;
    new.served_at := now();
    new.served_by := auth.uid();
  end if;
  return new;
end;
$$;

-- Pass the name to the sale INSERT trigger in the same transaction.
-- The existing complete_sale(jsonb) still handles pricing, stock and line items.
create or replace function public.complete_named_sale(lines jsonb, customer_name text) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to complete a sale'; end if;
  if customer_name is null or length(btrim(customer_name)) = 0 or length(btrim(customer_name)) > 80 then
    raise exception 'Customer name must contain 1 to 80 characters';
  end if;
  perform set_config('hankatsu.customer_name', btrim(customer_name), true);
  perform public.complete_sale(lines);
  perform set_config('hankatsu.customer_name', '', true);
end;
$$;
revoke all on function public.complete_named_sale(jsonb, text) from public, anon;
grant execute on function public.complete_named_sale(jsonb, text) to authenticated;
drop trigger if exists guard_service_status on public.sales;
create trigger guard_service_status before insert or update on public.sales
for each row execute function public.guard_service_status();

create or replace function public.mark_order_served(order_id text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role', '') <> 'admin' then
    raise exception 'Administrator access required';
  end if;
  update public.sales set service_status = 'served', served_at = now(), served_by = auth.uid()
  where id::text = order_id and service_status = 'pending';
  if not found then raise exception 'Order is already served or unavailable'; end if;
end;
$$;

create or replace function public.list_service_orders() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role', '') <> 'admin' then
    raise exception 'Administrator access required';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id::text, 'created_at', s.created_at, 'service_status', s.service_status,
    'customer_name', s.customer_name,
    'served_at', s.served_at, 'served_by', s.served_by,
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_name', i.product_name, 'qty', i.qty)), '[]'::jsonb)
              from public.sale_items i where i.sale_id = s.id)
  ) order by s.created_at), '[]'::jsonb) into result
  from public.sales s where s.service_status = 'pending' or s.id in
    (select id from public.sales where service_status = 'served' order by served_at desc limit 100);
  return result;
end;
$$;
revoke all on function public.mark_order_served(text) from public, anon;
revoke all on function public.list_service_orders() from public, anon;
grant execute on function public.mark_order_served(text) to authenticated;
grant execute on function public.list_service_orders() to authenticated;
commit;
