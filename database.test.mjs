import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
await db.exec(`
create role anon; create role authenticated; create schema auth;
create table auth.users(id uuid primary key,email text,raw_app_meta_data jsonb,raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
insert into auth.users values
('00000000-0000-0000-0000-000000000001','admin@test','{"role":"admin"}','{}'),
('00000000-0000-0000-0000-000000000002','cashier@test','{"role":"cashier"}','{}'),
('00000000-0000-0000-0000-000000000003','kitchen@test','{"role":"kitchen"}','{}'),
('00000000-0000-0000-0000-000000000004','unassigned@test','{}','{}');
create table public.products(id uuid primary key default gen_random_uuid(),name text not null,category text not null,price numeric(12,2) not null,stock integer not null,active boolean default true);
create table public.sales(id uuid primary key default gen_random_uuid(),total numeric not null,created_at timestamptz default now(),customer_name text,service_status text);
create table public.sale_items(id uuid default gen_random_uuid(),sale_id uuid references sales(id),product_id uuid,product_name text,qty integer,price numeric);
insert into sales(id,total,customer_name,service_status) values('10000000-0000-0000-0000-000000000001',50,'Historical','served');
insert into sale_items(sale_id,product_name,qty) values('10000000-0000-0000-0000-000000000001','Old meal',1);
`);
const sql = readFileSync('supabase/migrations/20260930_operational_pos.sql','utf8');
await db.exec(sql);
await db.exec(sql);
const api = async (action,args={}) => (await db.query('select public.pos_api($1,$2::jsonb) value',[action,JSON.stringify(args)])).rows[0].value;
const as = async n => db.query("select set_config('request.jwt.claim.sub',$1,false)",[`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`]);
const fails = async (fn,pattern) => assert.rejects(fn,pattern);
let passed=0;
async function test(name, fn) { await fn(); passed++; console.log('PASS '+name); }

await test('migration preserves history and is rerunnable', async()=> {
  assert.equal((await db.query('select count(*)::int n from pos_transactions')).rows[0].n,1);
  assert.equal((await db.query('select count(*)::int n from pos_lines')).rows[0].n,1);
});
await as(1);
let product;
await test('product creation records opening movement',async()=> {
  product=await api('create_product',{request_id:'create-product-001',name:'Katsu',category:'Meals',price_minor:10000,stock:3});
  assert.equal(product.stock,3);
  assert.equal((await api('stock_history',{product_id:product.id})).length,1);
});
await test('unassigned and kitchen accounts cannot sell or edit stock',async()=> {
  await as(4); await fails(()=>api('context'),/staff role/);
  await as(3); await fails(()=>api('checkout'),/Cashier/); await fails(()=>api('adjust_stock'),/Administrator/);
  await as(2); await fails(()=>api('create_product'),/Administrator/);
});
await as(2);
await test('checkout requires an open shift',async()=> {
  await fails(()=>api('checkout',{request_id:'checkout-request-001'}),/Open your cash shift/);
  await api('open_shift',{opening_minor:50000});
});
const request={request_id:'checkout-request-001',customer_name:'Maria',order_type:'takeaway',table_reference:'',lines:[{product_id:product.id,qty:2,unit_minor:10000}],total_minor:20000,cash_minor:25000};
let sale;
await test('sale records exact cash, snapshots, inventory and receipt',async()=> {
  sale=await api('checkout',request);
  assert.equal(sale.change_minor,5000); assert.equal(sale.lines[0].line_minor,20000);
  assert.equal((await api('catalog'))[0].stock,1);
});
await test('retry after lost response returns same receipt without another deduction',async()=> {
  const retry=await api('checkout',request);
  assert.equal(retry.id,sale.id); assert.equal(retry.receipt,sale.receipt);
  assert.equal((await api('catalog'))[0].stock,1);
  assert.equal((await api('lookup_checkout',{request_id:request.request_id})).id,sale.id);
});
await test('same request ID cannot change the purchase',async()=> {
  await fails(()=>api('checkout',{...request,customer_name:'Different'}),/different request/);
});
await test('stock and price checks rollback the entire transaction',async()=> {
  await fails(()=>api('checkout',{...request,request_id:'oversell-request-002'}),/Insufficient stock/);
  await fails(()=>api('checkout',{...request,request_id:'price-request-003',lines:[{product_id:product.id,qty:1,unit_minor:9000}]}),/Price changed/);
  assert.equal((await api('catalog'))[0].stock,1);
  assert.equal((await api('shift')).expected_minor,70000);
});
await test('direct table and internal function access is denied',async()=> {
  await db.exec('set role authenticated');
  await fails(()=>db.exec('update public.products set stock=999'),/permission denied/);
  await fails(()=>db.exec('select * from public.pos_transactions'),/permission denied/);
  await fails(()=>db.query('select public.pos_document($1)',[sale.id]),/permission denied/);
  await db.exec('reset role');
});
await as(3);
await test('kitchen transitions require current state and record names',async()=> {
  await fails(()=>api('transition',{id:sale.id,expected_status:'queued',target:'served'}),/Invalid/);
  await api('transition',{id:sale.id,expected_status:'queued',target:'preparing'});
  await fails(()=>api('transition',{id:sale.id,expected_status:'queued',target:'preparing'}),/Order changed/);
  await api('transition',{id:sale.id,expected_status:'preparing',target:'ready'});
  const served=await api('transition',{id:sale.id,expected_status:'ready',target:'served'});
  assert.equal(served.served_by_name,'kitchen@test'); assert.equal(served.events.length,4);
});
await as(1);
await test('stock adjustments compare old quantity and retain audit data',async()=> {
  await fails(()=>api('adjust_stock',{request_id:'adjust-request-001',product_id:product.id,expected_stock:3,quantity:10,reason:'Delivery'}),/Stock changed/);
  const adjusted=await api('adjust_stock',{request_id:'adjust-request-002',product_id:product.id,expected_stock:1,quantity:11,reason:'Delivery'});
  assert.equal(adjusted.delta,10);
});
await test('admin reversal returns cash once and restocks only when requested',async()=> {
  await api('open_shift',{opening_minor:50000});
  await api('reverse',{id:sale.id,target:'refunded',reason:'Wrong order',restock:false});
  await api('reverse',{id:sale.id,target:'refunded',reason:'Wrong order',restock:false});
  assert.equal((await api('catalog'))[0].stock,11);
  assert.equal((await api('shift')).expected_minor,30000);
});
await test('report uses Manila dates and separates gross and reversals',async()=> {
  const report=await api('report',{period:'daily'});
  assert.equal(report.timezone,'Asia/Manila'); assert.equal(report.reversal_minor,20000);
  assert.equal(report.net_minor,report.gross_minor-report.reversal_minor);
});
await test('cash difference requires a reason and closed shift blocks sales',async()=> {
  await fails(()=>api('close_shift',{counted_minor:1}),/Explain/);
  const closed=await api('close_shift',{counted_minor:30000,note:''});
  assert.ok(closed.closed_at);
  await fails(()=>api('checkout',{...request,request_id:'closed-shift-004'}),/Open your cash shift/);
});
await test('cashiers cannot read another cashier receipt or reopen served orders',async()=>{
  await as(2);
  await fails(()=>api('reopen',{id:sale.id}),/Administrator/);
  await db.exec("insert into auth.users values('00000000-0000-0000-0000-000000000005','other@test','{\"role\":\"cashier\"}','{}')");
  await as(5);await fails(()=>api('invoice',{id:sale.id}),/unavailable/);
  assert.equal(await api('lookup_checkout',{request_id:request.request_id}),null);
});
await test('invalid quantities and duplicate product lines are rejected',async()=>{
  await as(2);
  await fails(()=>api('checkout',{...request,request_id:'zero-quantity-001',lines:[{product_id:product.id,qty:0,unit_minor:10000}]}),/Invalid item quantity/);
  await fails(()=>api('checkout',{...request,request_id:'duplicate-lines-001',lines:[request.lines[0],request.lines[0]]}),/Combine duplicate/);
});
await test('stored receipt amounts survive later catalog changes',async()=>{
  await as(1);await db.query('update products set price=125,name=$1 where id=$2',['New menu name',product.id]);
  const doc=await api('invoice',{id:sale.id});assert.equal(doc.lines[0].product_name,'Katsu');assert.equal(doc.lines[0].unit_minor,10000);
  await db.query('update products set price=100,name=$1 where id=$2',['Katsu',product.id]);
});
await test('cursor pages do not duplicate invoices and exclude sales after snapshot',async()=>{
  await as(1);await api('adjust_stock',{request_id:'paging-stock-001',product_id:product.id,expected_stock:11,quantity:30,reason:'Test delivery'});
  await as(2);
  for(let i=0;i<12;i++)await api('checkout',{...request,request_id:`paging-checkout-${i}`,lines:[{product_id:product.id,qty:1,unit_minor:10000}],total_minor:10000,cash_minor:10000});
  const report=await api('report',{period:'daily'});
  const first=await api('invoices',{period:'daily',as_of:report.as_of});assert.equal(first.rows.length,10);
  await api('checkout',{...request,request_id:'after-snapshot-001',lines:[{product_id:product.id,qty:1,unit_minor:10000}],total_minor:10000,cash_minor:10000});
  const last=first.rows.at(-1);
  const second=await api('invoices',{period:'daily',as_of:report.as_of,cursor_time:last.created_at,cursor_id:last.id});
  assert.equal(first.count,second.count);assert.equal(new Set([...first.rows,...second.rows].map(x=>x.id)).size,first.count);
});
await test('competing requests for one remaining unit allow only one sale',async()=>{
  await as(1);const current=(await api('catalog'))[0];await api('adjust_stock',{request_id:'last-stock-001',product_id:product.id,expected_stock:current.stock,quantity:1,reason:'Stock count'});
  await as(2);
  const one={...request,lines:[{product_id:product.id,qty:1,unit_minor:10000}],total_minor:10000,cash_minor:10000};
  const results=await Promise.allSettled([api('checkout',{...one,request_id:'competing-one-001'}),api('checkout',{...one,request_id:'competing-two-001'})]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal((await api('catalog'))[0].stock,0);
});
console.log(`${passed} database checks passed (PGlite serializes connections; multi-session locking still requires staging verification)`);
await db.close();
