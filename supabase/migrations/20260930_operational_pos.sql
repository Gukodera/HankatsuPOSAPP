-- Run once during a maintenance window with all old app instances closed.
-- Keeps legacy tables and copies history without changing product quantities.
begin;
create table if not exists public.pos_config (
  id boolean primary key default true check(id), timezone text not null default 'Asia/Manila',
  cutoff_hour integer not null default 0 check(cutoff_hour between 0 and 23), version integer not null default 2
);
insert into public.pos_config(id) values(true) on conflict do nothing;
create sequence if not exists public.pos_receipt_seq;
create table if not exists public.pos_transactions (
  id text primary key default gen_random_uuid()::text,
  request_id text unique, request_body jsonb,
  receipt text not null unique default ('HK-' || lpad(nextval('public.pos_receipt_seq')::text, 8, '0')),
  created_at timestamptz not null default clock_timestamp(), customer_name text not null,
  order_type text not null default 'takeaway' check(order_type in ('takeaway','dine-in')),
  table_reference text, cashier_id uuid, cashier_name text,
  total_minor bigint not null check(total_minor >= 0), cash_minor bigint, change_minor bigint,
  payment_status text not null default 'paid' check(payment_status in ('paid','refunded','voided','legacy')),
  service_status text not null default 'queued' check(service_status in ('queued','preparing','ready','served','cancelled','unrecorded')),
  served_at timestamptz, served_by uuid, served_by_name text, reversed_at timestamptz,
  reversal_reason text, legacy boolean not null default false
);
create table if not exists public.pos_lines (
  id bigint generated always as identity primary key,
  transaction_id text not null references public.pos_transactions(id), product_id text,
  product_name text not null, qty integer not null check(qty > 0), unit_minor bigint, line_minor bigint
);
create table if not exists public.pos_events (
  id bigint generated always as identity primary key, transaction_id text not null references public.pos_transactions(id),
  created_at timestamptz not null default clock_timestamp(), actor_id uuid, actor_name text,
  action text not null, old_status text, new_status text, reason text
);
create table if not exists public.pos_stock_movements (
  id bigint generated always as identity primary key, request_id text unique,
  product_id text not null, product_name text not null, before_qty integer not null, after_qty integer not null,
  delta integer not null, reason text not null, note text, transaction_id text references public.pos_transactions(id),
  actor_id uuid, actor_name text, created_at timestamptz not null default clock_timestamp()
);
create table if not exists public.pos_shifts (
  id uuid primary key default gen_random_uuid(), actor_id uuid not null, actor_name text,
  opened_at timestamptz not null default clock_timestamp(), closed_at timestamptz,
  opening_minor bigint not null check(opening_minor >= 0), expected_minor bigint, counted_minor bigint,
  close_note text
);
create unique index if not exists pos_one_open_shift on public.pos_shifts(actor_id) where closed_at is null;
create table if not exists public.pos_cash_events (
  id bigint generated always as identity primary key, request_id text unique, shift_id uuid not null references public.pos_shifts(id),
  transaction_id text references public.pos_transactions(id), amount_minor bigint not null,
  reason text not null, created_at timestamptz not null default clock_timestamp()
);
create index if not exists pos_tx_date on public.pos_transactions(created_at desc, id);
create index if not exists pos_tx_service on public.pos_transactions(service_status,created_at,id);
create index if not exists pos_lines_transaction on public.pos_lines(transaction_id);
create index if not exists pos_stock_product on public.pos_stock_movements(product_id,id desc);
create index if not exists pos_events_transaction on public.pos_events(transaction_id,id);
create index if not exists pos_cash_shift on public.pos_cash_events(shift_id);

-- Snapshot legacy history exactly once. Unknown details remain NULL.
do $$
begin
  if to_regclass('public.products') is null then raise exception 'Existing products table is required'; end if;
  if to_regclass('public.sales') is not null then
    insert into public.pos_transactions(id,receipt,created_at,customer_name,total_minor,payment_status,service_status,served_at,served_by,legacy)
    select 'legacy:' || s.id::text, 'LEGACY-' || s.id::text, s.created_at,
      coalesce(to_jsonb(s)->>'customer_name','Name not recorded'), round(s.total * 100)::bigint,'legacy',
      case to_jsonb(s)->>'service_status' when 'pending' then 'queued' when 'served' then 'served' else 'unrecorded' end,
      (to_jsonb(s)->>'served_at')::timestamptz,(to_jsonb(s)->>'served_by')::uuid,true
    from public.sales s on conflict(id) do nothing;
    insert into public.pos_lines(transaction_id,product_id,product_name,qty,unit_minor,line_minor)
    select 'legacy:' || i.sale_id::text,to_jsonb(i)->>'product_id',i.product_name,i.qty,
      round(coalesce((to_jsonb(i)->>'unit_price')::numeric,(to_jsonb(i)->>'price')::numeric)*100)::bigint,
      round(coalesce((to_jsonb(i)->>'line_total')::numeric,(to_jsonb(i)->>'subtotal')::numeric)*100)::bigint
    from public.sale_items i where not exists(select 1 from public.pos_lines l where l.transaction_id='legacy:' || i.sale_id::text);
  end if;
end $$;

create or replace function public.pos_document(tx_id text) returns jsonb
language sql stable security definer set search_path = '' as $$
 select to_jsonb(t) - 'request_body' || jsonb_build_object(
   'lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.id) from public.pos_lines l where l.transaction_id=t.id),'[]'),
   'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.id) from public.pos_events e where e.transaction_id=t.id),'[]'))
 from public.pos_transactions t where t.id=tx_id;
$$;

create or replace function public.pos_api(action text, args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); staff_role text; staff_name text; cfg public.pos_config%rowtype;
  tx public.pos_transactions%rowtype; shift public.pos_shifts%rowtype;
  product public.products%rowtype; line jsonb; result jsonb; rows_json jsonb;
  request_key text := args->>'request_id'; amount bigint; subtotal bigint := 0; quantity integer;
  before_qty integer; next_qty integer; reason text; target text; current_status text;
  win_start timestamptz; win_end timestamptz; anchor date; cutoff timestamptz;
  limit_n integer := 10; offset_n integer := 0; total_count bigint; gross bigint; refunds bigint;
begin
  if uid is null then raise exception using errcode='42501',message='Sign in again to continue'; end if;
  select raw_app_meta_data->>'role',coalesce(raw_user_meta_data->>'display_name',email,id::text)
  into staff_role,staff_name from auth.users where id=uid;
  if staff_role is null or staff_role not in ('admin','cashier','kitchen') then
    raise exception using errcode='42501',message='Ask an administrator to assign your staff role';
  end if;
  select * into cfg from public.pos_config where id=true;
  if action='context' then
    return jsonb_build_object('role',staff_role,'name',staff_name,'timezone',cfg.timezone,'cutoff_hour',cfg.cutoff_hour,'version',cfg.version,
      'business_date',((clock_timestamp() at time zone cfg.timezone)-make_interval(hours=>cfg.cutoff_hour))::date);
  end if;
  if action in ('checkout','lookup_checkout','open_shift','shift','cash_movement','close_shift') and staff_role not in ('admin','cashier') then
    raise exception using errcode='42501',message='Cashier access required';
  end if;
  if action in ('create_product','adjust_stock','stock_history','reverse','reopen','shift_history') and staff_role <> 'admin' then
    raise exception using errcode='42501',message='Administrator access required';
  end if;
  if action in ('orders','transition') and staff_role not in ('admin','kitchen') then
    raise exception using errcode='42501',message='Kitchen or administrator access required';
  end if;
  if action in ('report','invoices','invoice','export') and staff_role not in ('admin','cashier') then
    raise exception using errcode='42501',message='Cashier access required';
  end if;

  if action='catalog' then
    limit_n := least(500,greatest(1,coalesce((args->>'limit')::integer,10)));
    offset_n := greatest(0,coalesce((args->>'offset')::integer,0));
    select coalesce(jsonb_agg(to_jsonb(p)),'[]') into rows_json from
      (select * from public.products where active=true and name ilike '%'||coalesce(args->>'query','')||'%'
       and (coalesce(args->>'availability','All')='All' or (args->>'availability'='Available' and stock>0) or (args->>'availability'='Sold out' and stock=0) or (args->>'availability'='Low stock' and stock between 1 and 5))
       order by name,id limit limit_n offset offset_n) p;
    return rows_json;
  elsif action='create_product' then
    if coalesce(length(btrim(args->>'name')),0) not between 1 and 120 or coalesce(length(args->>'category'),0) not between 1 and 60
      or (args->>'price_minor') is null or (args->>'price_minor')::bigint not between 0 and 100000000
      or (args->>'stock') is null or (args->>'stock')::integer not between 0 and 1000000 then
      raise exception 'Enter a name, category, valid price and nonnegative quantity';
    end if;
    if coalesce(length(request_key),0) not between 10 and 100 then raise exception 'Request ID required'; end if;
    perform pg_advisory_xact_lock(hashtextextended(request_key,0));
    select product_id into target from public.pos_stock_movements where request_id=request_key;
    if found then select * into product from public.products where id::text=target; return to_jsonb(product); end if;
    insert into public.products(name,category,price,stock,active) values(btrim(args->>'name'),args->>'category',(args->>'price_minor')::numeric/100,(args->>'stock')::integer,true) returning * into product;
    insert into public.pos_stock_movements(request_id,product_id,product_name,before_qty,after_qty,delta,reason,actor_id,actor_name)
    values(request_key,product.id::text,product.name,0,product.stock,product.stock,'Opening stock',uid,staff_name);
    return to_jsonb(product);
  elsif action='adjust_stock' then
    if coalesce(length(request_key),0) not between 10 and 100 then raise exception 'Request ID required'; end if;
    perform pg_advisory_xact_lock(hashtextextended(request_key,0));
    select to_jsonb(m) into result from public.pos_stock_movements m where request_id=request_key;
    if found then return result; end if;
    reason := btrim(args->>'reason');
    if coalesce(length(reason),0) not between 3 and 160 then raise exception 'An adjustment reason is required'; end if;
    select * into product from public.products where id::text=args->>'product_id' for update;
    if not found then raise exception 'Product not found'; end if;
    if (args->>'expected_stock') is null or product.stock <> (args->>'expected_stock')::integer then raise exception 'Stock changed. Refresh and review the adjustment'; end if;
    next_qty := (args->>'quantity')::integer;
    if next_qty is null or next_qty not between 0 and 1000000 then raise exception 'Quantity must be between 0 and 1000000'; end if;
    update public.products set stock=next_qty where id=product.id;
    insert into public.pos_stock_movements(request_id,product_id,product_name,before_qty,after_qty,delta,reason,note,actor_id,actor_name)
    values(request_key,product.id::text,product.name,product.stock,next_qty,next_qty-product.stock,reason,left(args->>'note',500),uid,staff_name) returning to_jsonb(pos_stock_movements.*) into result;
    return result;
  elsif action='stock_history' then
    select coalesce(jsonb_agg(to_jsonb(m) order by m.id desc),'[]') into result from
      (select * from public.pos_stock_movements where product_id=args->>'product_id'
       and ((args->>'before_id') is null or id<(args->>'before_id')::bigint) order by id desc limit 10) m;
    return result;
  elsif action='open_shift' then
    perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
    select * into shift from public.pos_shifts where actor_id=uid and closed_at is null;
    if found then return to_jsonb(shift); end if;
    amount := (args->>'opening_minor')::bigint;
    if amount is null or amount not between 0 and 10000000000 then raise exception 'Enter a valid opening cash amount'; end if;
    insert into public.pos_shifts(actor_id,actor_name,opening_minor) values(uid,staff_name,amount) returning * into shift;
    return to_jsonb(shift);
  elsif action in ('shift','cash_movement','close_shift') then
    select * into shift from public.pos_shifts where actor_id=uid and closed_at is null for update;
    if not found then
      if action='shift' then return 'null'::jsonb; end if;
      raise exception 'Open your cash shift first';
    end if;
    if action='cash_movement' then
      amount := (args->>'amount_minor')::bigint; reason := btrim(args->>'reason');
      if amount is null or amount=0 or abs(amount)>10000000000 or coalesce(length(reason),0)<3 or coalesce(length(request_key),0)<10 then raise exception 'Enter an amount, reason and request ID'; end if;
      insert into public.pos_cash_events(request_id,shift_id,amount_minor,reason) values(request_key,shift.id,amount,left(reason,500)) on conflict(request_id) do nothing;
    end if;
    select shift.opening_minor + coalesce(sum(amount_minor),0) into amount from public.pos_cash_events where shift_id=shift.id;
    if action='close_shift' then
      if (args->>'counted_minor') is null or (args->>'counted_minor')::bigint<0 then raise exception 'Enter counted cash'; end if;
      if amount<>(args->>'counted_minor')::bigint and coalesce(length(btrim(args->>'note')),0)<3 then raise exception 'Explain the cash difference before closing'; end if;
      update public.pos_shifts set closed_at=clock_timestamp(),expected_minor=amount,counted_minor=(args->>'counted_minor')::bigint,close_note=left(args->>'note',500) where id=shift.id returning * into shift;
    end if;
    return to_jsonb(shift)||jsonb_build_object('expected_minor',amount,'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.id desc) from public.pos_cash_events e where shift_id=shift.id),'[]'));
  elsif action='shift_history' then
    select coalesce(jsonb_agg(to_jsonb(s) order by s.opened_at desc),'[]') into result from
      (select * from public.pos_shifts order by opened_at desc limit 10 offset greatest(0,coalesce((args->>'offset')::integer,0))) s;
    return result;
  elsif action='lookup_checkout' then
    select * into tx from public.pos_transactions where request_id=request_key and cashier_id=uid;
    if not found then return 'null'::jsonb; end if;
    return public.pos_document(tx.id);
  elsif action='checkout' then
    if coalesce(length(request_key),0) not between 10 and 100 then raise exception 'Checkout ID required'; end if;
    perform pg_advisory_xact_lock(hashtextextended(request_key,0));
    select * into tx from public.pos_transactions where request_id=request_key;
    if found then
      if tx.cashier_id<>uid or tx.request_body is distinct from args then raise exception 'This checkout ID belongs to a different request'; end if;
      return public.pos_document(tx.id);
    end if;
    select * into shift from public.pos_shifts where actor_id=uid and closed_at is null for update;
    if not found then raise exception 'Open your cash shift before accepting payment'; end if;
    if coalesce(length(btrim(args->>'customer_name')),0) not between 1 and 80 then raise exception 'Customer name is required'; end if;
    if args->>'order_type' not in ('dine-in','takeaway') or args->>'order_type' is null then raise exception 'Choose dine-in or takeaway'; end if;
    if args->>'order_type'='dine-in' and coalesce(length(btrim(args->>'table_reference')),0) not between 1 and 40 then raise exception 'Enter the table reference'; end if;
    if jsonb_typeof(args->'lines') is distinct from 'array' or jsonb_array_length(args->'lines') not between 1 and 200 then raise exception 'The cart must contain 1 to 200 products'; end if;
    if (select count(*)<>count(distinct x->>'product_id') from jsonb_array_elements(args->'lines') x) then raise exception 'Combine duplicate products before checkout'; end if;
    -- Lock in product ID order to prevent competing checkouts from overselling.
    for line in select x from jsonb_array_elements(args->'lines') x order by x->>'product_id' loop
      quantity := (line->>'qty')::integer;
      if quantity is null or quantity not between 1 and 1000000 then raise exception 'Invalid item quantity'; end if;
      select * into product from public.products where id::text=line->>'product_id' and active=true for update;
      if not found then raise exception 'A product is no longer available. Refresh the menu'; end if;
      if product.price<0 or product.price::text in ('NaN','Infinity','-Infinity') or product.stock<quantity then raise exception 'Insufficient stock or invalid price for %',product.name; end if;
      if (line->>'unit_minor') is null or round(product.price*100)::bigint<>(line->>'unit_minor')::bigint then raise exception 'Price changed for %. Refresh and reconfirm payment',product.name; end if;
      subtotal := subtotal + round(product.price*100)::bigint*quantity;
    end loop;
    amount := (args->>'cash_minor')::bigint;
    if amount is null or amount<subtotal or amount>10000000000 or (args->>'total_minor') is null or (args->>'total_minor')::bigint<>subtotal then raise exception 'Payment amount changed. Review the total and cash received'; end if;
    insert into public.pos_transactions(request_id,request_body,customer_name,order_type,table_reference,cashier_id,cashier_name,total_minor,cash_minor,change_minor)
    values(request_key,args,btrim(args->>'customer_name'),args->>'order_type',left(args->>'table_reference',40),uid,staff_name,subtotal,amount,amount-subtotal) returning * into tx;
    for line in select x from jsonb_array_elements(args->'lines') x order by x->>'product_id' loop
      select * into product from public.products where id::text=line->>'product_id';
      quantity := (line->>'qty')::integer;
      insert into public.pos_lines(transaction_id,product_id,product_name,qty,unit_minor,line_minor)
      values(tx.id,product.id::text,product.name,quantity,round(product.price*100)::bigint,round(product.price*100)::bigint*quantity);
      update public.products set stock=stock-quantity where id=product.id;
      insert into public.pos_stock_movements(product_id,product_name,before_qty,after_qty,delta,reason,transaction_id,actor_id,actor_name)
      values(product.id::text,product.name,product.stock,product.stock-quantity,-quantity,'Sale',tx.id,uid,staff_name);
    end loop;
    insert into public.pos_cash_events(shift_id,transaction_id,amount_minor,reason) values(shift.id,tx.id,subtotal,'Sale '||tx.receipt);
    insert into public.pos_events(transaction_id,actor_id,actor_name,action,new_status) values(tx.id,uid,staff_name,'paid','queued');
    return public.pos_document(tx.id);
  elsif action in ('transition','reopen','reverse') then
    select * into tx from public.pos_transactions where id=args->>'id' for update;
    if not found then raise exception 'Order not found'; end if;
    reason := btrim(args->>'reason'); target := args->>'target';
    if action='reverse' then
      if tx.payment_status in ('refunded','voided') then return public.pos_document(tx.id); end if;
      if tx.legacy then raise exception 'Legacy payment details are unknown. Reconcile this transaction separately'; end if;
      if coalesce(length(reason),0)<3 or target is null or target not in ('refunded','voided') then raise exception 'Choose a correction type and enter a reason'; end if;
      select * into shift from public.pos_shifts where actor_id=uid and closed_at is null for update;
      if not found then raise exception 'Open your cash shift to record the money returned'; end if;
      if coalesce((args->>'restock')::boolean,false) then
        for line in select to_jsonb(l) from public.pos_lines l where transaction_id=tx.id order by product_id loop
          select * into product from public.products where id::text=line->>'product_id' for update;
          if not found then raise exception 'A product is missing. Correct without restocking'; end if;
          quantity := (line->>'qty')::integer;
          update public.products set stock=stock+quantity where id=product.id;
          insert into public.pos_stock_movements(product_id,product_name,before_qty,after_qty,delta,reason,transaction_id,actor_id,actor_name)
          values(product.id::text,product.name,product.stock,product.stock+quantity,quantity,'Reversal: '||reason,tx.id,uid,staff_name);
        end loop;
      end if;
      update public.pos_transactions set payment_status=target,service_status='cancelled',reversed_at=clock_timestamp(),reversal_reason=reason where id=tx.id;
      insert into public.pos_cash_events(shift_id,transaction_id,amount_minor,reason) values(shift.id,tx.id,-tx.total_minor,target||': '||reason);
      insert into public.pos_events(transaction_id,actor_id,actor_name,action,old_status,new_status,reason) values(tx.id,uid,staff_name,target,tx.payment_status,target,reason);
    else
      if tx.payment_status not in ('paid','legacy') then raise exception 'This order was reversed'; end if;
      if tx.service_status is distinct from args->>'expected_status' then raise exception 'Order changed. Refresh before continuing'; end if;
      if action='reopen' then
        if coalesce(length(reason),0)<3 or tx.service_status not in ('served','preparing','ready') then raise exception 'Enter a reason to reopen this order'; end if;
        target := 'queued';
      elsif not ((tx.service_status='queued' and target='preparing') or (tx.service_status='preparing' and target='ready') or (tx.service_status='ready' and target='served')) or target is null then raise exception 'Invalid order transition'; end if;
      update public.pos_transactions set service_status=target,
        served_at=case when target='served' then clock_timestamp() else null end,
        served_by=case when target='served' then uid else null end,
        served_by_name=case when target='served' then staff_name else null end where id=tx.id;
      insert into public.pos_events(transaction_id,actor_id,actor_name,action,old_status,new_status,reason) values(tx.id,uid,staff_name,action,tx.service_status,target,reason);
    end if;
    return public.pos_document(tx.id);
  elsif action='invoice' then
    select * into tx from public.pos_transactions where id=args->>'id';
    if not found or (staff_role='cashier' and tx.cashier_id is distinct from uid) then raise exception using errcode='42501',message='Invoice unavailable for this account'; end if;
    return public.pos_document(tx.id);
  elsif action='orders' then
    select count(*) into total_count from public.pos_transactions t where t.service_status=coalesce(args->>'status','queued')
      and (t.customer_name||' '||t.receipt||' '||coalesce(t.table_reference,'')) ilike '%'||coalesce(args->>'query','')||'%';
    select coalesce(jsonb_agg(public.pos_document(t.id) order by t.created_at,t.id),'[]') into result from
      (select * from public.pos_transactions t where service_status=coalesce(args->>'status','queued')
        and (t.customer_name||' '||t.receipt||' '||coalesce(t.table_reference,'')) ilike '%'||coalesce(args->>'query','')||'%'
        and ((args->>'cursor_time') is null or (t.created_at,t.id)>((args->>'cursor_time')::timestamptz,args->>'cursor_id'))
        order by created_at,id limit 10) t;
    return jsonb_build_object('rows',result,'count',total_count,'refreshed_at',clock_timestamp());
  elsif action in ('report','invoices','export') then
    anchor := coalesce((args->>'date')::date,((clock_timestamp() at time zone cfg.timezone)-make_interval(hours=>cfg.cutoff_hour))::date);
    if coalesce(args->>'period','daily')='weekly' then anchor:=anchor-(extract(isodow from anchor)::int-1);
    elsif args->>'period'='monthly' then anchor:=date_trunc('month',anchor)::date;
    elsif coalesce(args->>'period','daily')<>'daily' then raise exception 'Invalid reporting period'; end if;
    win_start := (anchor+make_interval(hours=>cfg.cutoff_hour)) at time zone cfg.timezone;
    win_end := ((case args->>'period' when 'weekly' then anchor+7 when 'monthly' then (anchor+interval '1 month')::date else anchor+1 end)+make_interval(hours=>cfg.cutoff_hour)) at time zone cfg.timezone;
    cutoff := least(coalesce((args->>'as_of')::timestamptz,clock_timestamp()),clock_timestamp());
    if action='report' then
      select coalesce(sum(total_minor),0),count(*) into gross,total_count from public.pos_transactions t where created_at>=win_start and created_at<win_end and created_at<=cutoff and (staff_role='admin' or cashier_id=uid);
      select coalesce(sum(total_minor),0) into refunds from public.pos_transactions t where reversed_at>=win_start and reversed_at<win_end and reversed_at<=cutoff and (staff_role='admin' or cashier_id=uid);
      select coalesce(jsonb_agg(to_jsonb(b)),'[]') into result from
        (select l.product_name,sum(l.qty) qty from public.pos_lines l join public.pos_transactions t on t.id=l.transaction_id
         where t.created_at>=win_start and t.created_at<win_end and t.created_at<=cutoff and (staff_role='admin' or t.cashier_id=uid)
         group by l.product_name order by sum(l.qty) desc,l.product_name limit 5) b;
      select coalesce(jsonb_agg(to_jsonb(b) order by bucket),'[]') into rows_json from
        (select case when args->>'period'='daily' then to_char(created_at at time zone cfg.timezone,'HH24') else to_char((created_at at time zone cfg.timezone)-make_interval(hours=>cfg.cutoff_hour),'YYYY-MM-DD') end bucket,
         sum(total_minor) total_minor from public.pos_transactions t where created_at>=win_start and created_at<win_end and created_at<=cutoff and (staff_role='admin' or cashier_id=uid) group by 1) b;
      return jsonb_build_object('start',win_start,'end',win_end,'as_of',cutoff,'timezone',cfg.timezone,'date',anchor,'gross_minor',gross,'reversal_minor',refunds,'net_minor',gross-refunds,'count',total_count,'best',result,'buckets',rows_json,'scope',case when staff_role='admin' then 'Store' else 'My sales' end);
    end if;
    select count(*) into total_count from public.pos_transactions t where created_at>=win_start and created_at<win_end and created_at<=cutoff and (staff_role='admin' or cashier_id=uid)
      and (customer_name||' '||receipt) ilike '%'||coalesce(args->>'query','')||'%'
      and (coalesce(args->>'payment','all')='all' or (case when reversed_at>cutoff then 'paid' else payment_status end)=args->>'payment');
    select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc,t.id desc),'[]') into result from
      (select id,receipt,customer_name,created_at,total_minor,
        case when reversed_at>cutoff then 'paid' else payment_status end payment_status
       from public.pos_transactions t where created_at>=win_start and created_at<win_end and created_at<=cutoff and (staff_role='admin' or cashier_id=uid)
       and (customer_name||' '||receipt) ilike '%'||coalesce(args->>'query','')||'%'
       and (coalesce(args->>'payment','all')='all' or (case when reversed_at>cutoff then 'paid' else payment_status end)=args->>'payment')
       and ((args->>'cursor_time') is null or (created_at,id)<((args->>'cursor_time')::timestamptz,args->>'cursor_id'))
       order by created_at desc,id desc limit 10) t;
    return jsonb_build_object('rows',result,'count',total_count,'as_of',cutoff);
  end if;
  raise exception 'Unknown POS action';
end;
$$;

-- Only the guarded RPC can mutate the operational ledger.
do $$ declare obj record; col record; begin
  for obj in select tablename from pg_tables where schemaname='public' and tablename like 'pos\_%' escape '\' loop
    execute format('alter table public.%I enable row level security',obj.tablename);
    execute format('revoke all on table public.%I from public,anon,authenticated',obj.tablename);
  end loop;
  for obj in select c.oid::regclass rel from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('products','sales','sale_items') loop
    execute format('revoke all on table %s from public,anon,authenticated',obj.rel);
    for col in select attname from pg_attribute where attrelid=obj.rel and attnum>0 and not attisdropped loop
      execute format('revoke all (%I) on table %s from public,anon,authenticated',col.attname,obj.rel);
    end loop;
  end loop;
  for obj in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('complete_sale','complete_named_sale','mark_order_served','list_service_orders','pos_document','pos_api') loop
    execute format('revoke all on function %s from public,anon,authenticated',obj.signature);
  end loop;
end $$;
grant execute on function public.pos_api(text,jsonb) to authenticated;
commit;
