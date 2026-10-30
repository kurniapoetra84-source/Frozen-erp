-- Frozen ERP schema v0.1
-- Jalankan seluruh file ini di Supabase SQL Editor pada project baru.
create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('owner','admin','sales','warehouse','delivery','finance');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role public.app_role not null default 'sales',
  created_at timestamptz not null default now()
);

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid()); $$;

create or replace function public.has_role(allowed public.app_role[])
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role = any(allowed)); $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id, full_name, role)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), 'sales')
  on conflict(id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  code text unique not null default 'WH-01',
  name text not null default 'Gudang Utama',
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.warehouses(code,name) values('WH-01','Gudang Utama') on conflict(code) do nothing;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(), name text unique not null,
  created_at timestamptz not null default now()
);
create table if not exists public.units (
  id uuid primary key default gen_random_uuid(), name text unique not null,
  abbreviation text not null
);
insert into public.units(name,abbreviation) values ('Kilogram','kg'),('Pcs','pcs'),('Karton','ctn'),('Pack','pack')
on conflict(name) do nothing;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text unique not null, name text not null, category text, unit text not null default 'pcs',
  purchase_price numeric(16,2) not null default 0 check(purchase_price>=0),
  selling_price numeric(16,2) not null default 0 check(selling_price>=0),
  minimum_stock numeric(16,3) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(), name text not null,
  phone text, email text, address text, notes text, created_at timestamptz not null default now()
);
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(), name text not null,
  phone text, email text, address text, credit_limit numeric(16,2) not null default 0,
  notes text, created_at timestamptz not null default now()
);

create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(), po_number text unique not null,
  supplier_id uuid references public.suppliers(id), supplier_name text,
  order_date date not null default current_date, status text not null default 'draft'
    check(status in ('draft','ordered','partial','received','cancelled')),
  subtotal numeric(16,2) not null default 0, discount numeric(16,2) not null default 0,
  total numeric(16,2) not null default 0, notes text, created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(), purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  product_id uuid not null references public.products(id), qty numeric(16,3) not null check(qty>0),
  unit_cost numeric(16,2) not null default 0, line_total numeric(16,2) generated always as (qty*unit_cost) stored
);
create table if not exists public.goods_receipts (
  id uuid primary key default gen_random_uuid(), receipt_number text unique not null,
  purchase_order_id uuid references public.purchase_orders(id), supplier_id uuid references public.suppliers(id),
  received_at date not null default current_date, warehouse_id uuid references public.warehouses(id),
  notes text, received_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.stock_batches (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id),
  batch_no text not null, expiry_date date not null, qty_received numeric(16,3) not null default 0,
  qty_available numeric(16,3) not null default 0 check(qty_available>=0),
  unit_cost numeric(16,2) not null default 0, warehouse_id uuid references public.warehouses(id),
  goods_receipt_id uuid references public.goods_receipts(id), created_at timestamptz not null default now(),
  unique(product_id,batch_no,warehouse_id)
);
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id),
  batch_id uuid references public.stock_batches(id), movement_date timestamptz not null default now(),
  movement_type text not null check(movement_type in ('opening','receipt','sale','adjustment_in','adjustment_out','return')),
  reference_type text, reference_id uuid, qty_in numeric(16,3) not null default 0,
  qty_out numeric(16,3) not null default 0, balance_after numeric(16,3), notes text,
  created_by uuid references auth.users(id)
);

create table if not exists public.sales_orders (
  id uuid primary key default gen_random_uuid(), so_number text unique not null,
  customer_id uuid references public.customers(id), customer_name text,
  order_date date not null default current_date, status text not null default 'draft'
    check(status in ('draft','confirmed','processing','shipped','completed','cancelled')),
  subtotal numeric(16,2) not null default 0, discount numeric(16,2) not null default 0,
  shipping_cost numeric(16,2) not null default 0, total numeric(16,2) not null default 0,
  notes text, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.sales_order_lines (
  id uuid primary key default gen_random_uuid(), sales_order_id uuid not null references public.sales_orders(id) on delete cascade,
  product_id uuid not null references public.products(id), qty numeric(16,3) not null check(qty>0),
  unit_price numeric(16,2) not null default 0, line_total numeric(16,2) generated always as (qty*unit_price) stored
);
create table if not exists public.delivery_orders (
  id uuid primary key default gen_random_uuid(), do_number text unique not null,
  sales_order_id uuid references public.sales_orders(id), customer_id uuid references public.customers(id),
  delivery_date date not null default current_date, status text not null default 'draft',
  recipient_name text, delivery_address text, notes text, delivered_at timestamptz,
  created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.delivery_order_lines (
  id uuid primary key default gen_random_uuid(), delivery_order_id uuid not null references public.delivery_orders(id) on delete cascade,
  product_id uuid not null references public.products(id), batch_id uuid references public.stock_batches(id),
  qty numeric(16,3) not null check(qty>0)
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(), invoice_number text unique not null,
  sales_order_id uuid references public.sales_orders(id), customer_id uuid references public.customers(id),
  invoice_date date not null default current_date, due_date date,
  subtotal numeric(16,2) not null default 0, tax numeric(16,2) not null default 0,
  total numeric(16,2) not null default 0, paid_amount numeric(16,2) not null default 0,
  status text not null default 'unpaid' check(status in ('unpaid','partial','paid','void')),
  created_at timestamptz not null default now()
);
create table if not exists public.customer_payments (
  id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id),
  payment_date date not null default current_date, amount numeric(16,2) not null check(amount>0),
  payment_method text not null default 'transfer', reference_no text, notes text,
  received_by uuid references auth.users(id), created_at timestamptz not null default now()
);

create table if not exists public.supplier_bills (
  id uuid primary key default gen_random_uuid(), bill_number text unique not null,
  purchase_order_id uuid references public.purchase_orders(id), supplier_id uuid references public.suppliers(id),
  bill_date date not null default current_date, due_date date, total numeric(16,2) not null default 0,
  paid_amount numeric(16,2) not null default 0, status text not null default 'unpaid',
  created_at timestamptz not null default now()
);
create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(), supplier_bill_id uuid not null references public.supplier_bills(id),
  payment_date date not null default current_date, amount numeric(16,2) not null check(amount>0),
  payment_method text not null default 'transfer', reference_no text, notes text,
  created_at timestamptz not null default now()
);
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(), expense_date date not null default current_date,
  category text not null, description text, amount numeric(16,2) not null check(amount>=0),
  payment_method text, reference_no text, created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- Keep invoice/payment balance synchronized.
create or replace function public.apply_customer_payment()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_total numeric(16,2); v_paid numeric(16,2);
begin
  select total into v_total from public.invoices where id=new.invoice_id for update;
  select coalesce(sum(amount),0) into v_paid from public.customer_payments where invoice_id=new.invoice_id;
  update public.invoices set paid_amount=v_paid,
    status=case when v_paid>=v_total then 'paid' when v_paid>0 then 'partial' else 'unpaid' end
  where id=new.invoice_id;
  return new;
end; $$;
drop trigger if exists customer_payment_after_insert on public.customer_payments;
create trigger customer_payment_after_insert after insert on public.customer_payments
for each row execute procedure public.apply_customer_payment();

create or replace function public.apply_supplier_payment()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_total numeric(16,2); v_paid numeric(16,2);
begin
  select total into v_total from public.supplier_bills where id=new.supplier_bill_id for update;
  select coalesce(sum(amount),0) into v_paid from public.supplier_payments where supplier_bill_id=new.supplier_bill_id;
  update public.supplier_bills set paid_amount=v_paid,
    status=case when v_paid>=v_total then 'paid' when v_paid>0 then 'partial' else 'unpaid' end
  where id=new.supplier_bill_id;
  return new;
end; $$;
drop trigger if exists supplier_payment_after_insert on public.supplier_payments;
create trigger supplier_payment_after_insert after insert on public.supplier_payments
for each row execute procedure public.apply_supplier_payment();

-- FEFO allocation: consume earliest expiry batch first. Transaction-safe RPC.
create or replace function public.allocate_fefo(p_product_id uuid, p_qty numeric, p_reference_type text, p_reference_id uuid)
returns table(batch_id uuid, allocated_qty numeric)
language plpgsql security definer set search_path=public
as $$
declare b record; remaining numeric := p_qty; take_qty numeric;
begin
  if p_qty<=0 then raise exception 'Jumlah harus lebih dari nol'; end if;
  for b in select id, qty_available from public.stock_batches
    where product_id=p_product_id and qty_available>0 and expiry_date>=current_date
    order by expiry_date asc, created_at asc for update
  loop
    exit when remaining<=0;
    take_qty := least(b.qty_available,remaining);
    update public.stock_batches set qty_available=qty_available-take_qty where id=b.id;
    insert into public.stock_movements(product_id,batch_id,movement_type,reference_type,reference_id,qty_out)
      values(p_product_id,b.id,'sale',p_reference_type,p_reference_id,take_qty);
    batch_id := b.id; allocated_qty := take_qty; return next;
    remaining := remaining-take_qty;
  end loop;
  if remaining>0 then raise exception 'Stok tersedia tidak mencukupi. Kekurangan: %', remaining; end if;
end; $$;

-- Initial policies: authenticated staff can read; writes restricted by role.
alter table public.profiles enable row level security;
alter table public.warehouses enable row level security;
alter table public.categories enable row level security;
alter table public.units enable row level security;
alter table public.products enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_lines enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.stock_batches enable row level security;
alter table public.stock_movements enable row level security;
alter table public.sales_orders enable row level security;
alter table public.sales_order_lines enable row level security;
alter table public.delivery_orders enable row level security;
alter table public.delivery_order_lines enable row level security;
alter table public.invoices enable row level security;
alter table public.customer_payments enable row level security;
alter table public.supplier_bills enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.expenses enable row level security;

-- Profiles: users see own profile; owner/admin can manage all profiles.
create policy "profiles read own or admin" on public.profiles for select to authenticated
using (id=auth.uid() or public.has_role(array['owner','admin']::public.app_role[]));
create policy "profiles update own" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy "profiles admin insert" on public.profiles for insert to authenticated
with check(public.has_role(array['owner','admin']::public.app_role[]));

-- Staff read policies for all ERP tables.
do $$
declare t text;
begin
 foreach t in array array['warehouses','categories','units','products','suppliers','customers','purchase_orders','purchase_order_lines','goods_receipts','stock_batches','stock_movements','sales_orders','sales_order_lines','delivery_orders','delivery_order_lines','invoices','customer_payments','supplier_bills','supplier_payments','expenses']
 loop
  execute format('create policy %I on public.%I for select to authenticated using (public.is_staff())', t||'_staff_read', t);
 end loop;
end $$;

-- Role-aware writes: initial broad operational permissions, excluding role/profile administration.
do $$
declare t text;
begin
 foreach t in array array['warehouses','categories','units','products','suppliers','customers','purchase_orders','purchase_order_lines','goods_receipts','stock_batches','stock_movements','sales_orders','sales_order_lines','delivery_orders','delivery_order_lines','invoices','customer_payments','supplier_bills','supplier_payments','expenses']
 loop
  execute format('create policy %I on public.%I for all to authenticated using (public.has_role(array[''owner'',''admin'',''sales'',''warehouse'',''delivery'',''finance'']::public.app_role[])) with check (public.has_role(array[''owner'',''admin'',''sales'',''warehouse'',''delivery'',''finance'']::public.app_role[]))', t||'_staff_write', t);
 end loop;
end $$;

-- Bootstrap: after first user signs up, run this once in SQL editor to grant Owner.
-- update public.profiles set role='owner', full_name='Owner' where id=(select id from auth.users order by created_at asc limit 1);

create or replace view public.v_stock_by_product as
select p.id,p.sku,p.name,p.unit,coalesce(sum(b.qty_available),0) as qty_available,
       min(b.expiry_date) filter(where b.qty_available>0) as nearest_expiry
from public.products p left join public.stock_batches b on b.product_id=p.id
group by p.id,p.sku,p.name,p.unit;

create or replace view public.v_receivables as
select i.id,i.invoice_number,i.invoice_date,i.due_date,i.total,i.paid_amount,
       greatest(i.total-i.paid_amount,0) as outstanding,c.name as customer_name
from public.invoices i left join public.customers c on c.id=i.customer_id
where i.status in ('unpaid','partial');
create or replace view public.v_payables as
select b.id,b.bill_number,b.bill_date,b.due_date,b.total,b.paid_amount,
       greatest(b.total-b.paid_amount,0) as outstanding,s.name as supplier_name
from public.supplier_bills b left join public.suppliers s on s.id=b.supplier_id
where b.status in ('unpaid','partial');
