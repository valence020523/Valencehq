-- ============================================================
-- VALENCE — products table
-- Run this in the Supabase SQL editor.
-- Safe to run on a fresh project; if you already have a `products`
-- table from the original verify-authenticity flow, use the
-- ALTER TABLE block further down instead of the CREATE TABLE.
-- ============================================================

create table if not exists products (
  id              uuid primary key default gen_random_uuid(),
  qr_code         text not null unique,
  product_name    text,
  batch_number    text,

  -- edition / serialization
  item_number     text,                 -- e.g. "VAL-0489" — shown as the serial on the reveal
  edition_name    text,                 -- e.g. "Genesis Vault — Limited Edition"
  edition_total   integer,              -- e.g. 500 — renders "0489 of 500"

  -- registration / ownership
  owner_name      text,                 -- masked on the public reveal page
  registered_at   date,

  -- anti-counterfeiting
  security_hash   text,                 -- unique token stamped on the physical tag

  manufactured_at date,
  created_at      timestamptz not null default now()
);

create index if not exists products_qr_code_idx on products (qr_code);

-- ------------------------------------------------------------
-- If the table already exists from before, run this instead:
-- ------------------------------------------------------------
-- alter table products add column if not exists item_number text;
-- alter table products add column if not exists edition_name text;
-- alter table products add column if not exists edition_total integer;
-- alter table products add column if not exists owner_name text;
-- alter table products add column if not exists registered_at date;
-- alter table products add column if not exists security_hash text;

-- ------------------------------------------------------------
-- Row Level Security — public can look up a product by QR code
-- (needed for the verify-authenticity / product.html scan flow),
-- but only the signed-in admin account can insert new products.
-- Adjust the email to match ADMIN_EMAIL in verifyadmin.html.
-- ------------------------------------------------------------
alter table products enable row level security;

drop policy if exists "Public can read products" on products;
create policy "Public can read products"
  on products for select
  using (true);

drop policy if exists "Only admin can insert products" on products;
create policy "Only admin can insert products"
  on products for insert
  with check (auth.jwt() ->> 'email' = 'mhilesjr@gmail.com');

drop policy if exists "Only admin can update products" on products;
create policy "Only admin can update products"
  on products for update
  using (auth.jwt() ->> 'email' = 'mhilesjr@gmail.com');
