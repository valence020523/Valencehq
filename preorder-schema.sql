-- ============================================================
-- VALENCE — pre-order listings + customer reservations
-- Run this in the Supabase SQL editor.
-- ============================================================

-- ---------- 1. Listings ----------
-- One row per item open for pre-order. Add rows yourself for now
-- (Supabase dashboard -> Table Editor), or build an admin panel later.
create table if not exists public.preorder_listings (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  image_url text,
  price_cents integer,
  release_date date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.preorder_listings enable row level security;

-- Anyone signed in can browse open listings.
drop policy if exists "authenticated can view active listings" on public.preorder_listings;
create policy "authenticated can view active listings" on public.preorder_listings
  for select
  using (active = true);

-- ---------- 2. Reservations ----------
-- One row per customer per listing they've pre-ordered, including the
-- 50% deposit details and receipt collected at checkout.
create table if not exists public.preorder_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.preorder_listings(id) on delete cascade,
  full_name text not null,
  deposit_amount_cents integer not null,
  payment_method text not null check (payment_method in ('card', 'bank_transfer', 'mobile_money', 'cash')),
  receipt_path text not null,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  unique (user_id, listing_id)
);

create index if not exists preorder_reservations_user_id_idx on public.preorder_reservations (user_id);

alter table public.preorder_reservations enable row level security;

-- Customers can see and create only their own reservations.
drop policy if exists "users can view their own reservations" on public.preorder_reservations;
create policy "users can view their own reservations" on public.preorder_reservations
  for select
  using (auth.uid() = user_id);

drop policy if exists "users can create their own reservations" on public.preorder_reservations;
create policy "users can create their own reservations" on public.preorder_reservations
  for insert
  with check (auth.uid() = user_id);

-- Admin (preorderadmin.html, keep in sync with ADMIN_EMAIL there) can see
-- and update every reservation, e.g. to mark deposits as verified/paid.
drop policy if exists "admin can view all reservations" on public.preorder_reservations;
create policy "admin can view all reservations" on public.preorder_reservations
  for select
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

drop policy if exists "admin can update reservations" on public.preorder_reservations;
create policy "admin can update reservations" on public.preorder_reservations
  for update
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

-- ---------- 3. Admin can add/update listings too ----------
drop policy if exists "admin can insert listings" on public.preorder_listings;
create policy "admin can insert listings" on public.preorder_listings
  for insert
  with check ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

drop policy if exists "admin can update listings" on public.preorder_listings;
create policy "admin can update listings" on public.preorder_listings
  for update
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

drop policy if exists "admin can view all listings" on public.preorder_listings;
create policy "admin can view all listings" on public.preorder_listings
  for select
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

-- ---------- 4. Receipt storage ----------
-- Private bucket: customers upload their own receipt, only they and the
-- admin can read it back. preorder.html uploads here; preorderadmin.html
-- generates short-lived signed URLs to display them.
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

drop policy if exists "users can upload their own receipts" on storage.objects;
create policy "users can upload their own receipts" on storage.objects
  for insert
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "users can view their own receipts" on storage.objects;
create policy "users can view their own receipts" on storage.objects
  for select
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "admin can view all receipts" on storage.objects;
create policy "admin can view all receipts" on storage.objects
  for select
  using (
    bucket_id = 'receipts'
    and (auth.jwt() ->> 'email') = 'mhilesjr@gmail.com'
  );
