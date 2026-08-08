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
  price_cents integer, -- stored in kobo (₦1 = 100 kobo), matches Paystack's amount unit for NGN
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
-- One row per customer per listing they've pre-ordered. Rows are written
-- by the verify-paystack-payment Edge Function ONLY, after it confirms
-- the transaction directly with Paystack — never by the client directly,
-- so a customer can't fake a "paid" reservation.
create table if not exists public.preorder_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.preorder_listings(id) on delete cascade,
  full_name text not null,
  deposit_amount_cents integer not null, -- kobo (₦1 = 100 kobo)
  payment_method text not null default 'paystack' check (payment_method in ('paystack', 'card', 'bank_transfer', 'mobile_money', 'cash')),
  paystack_reference text unique,
  receipt_path text,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  unique (user_id, listing_id)
);

-- If you're upgrading an existing table from the manual-receipt version:
-- alter table public.preorder_reservations add column if not exists paystack_reference text unique;
-- alter table public.preorder_reservations alter column receipt_path drop not null;
-- alter table public.preorder_reservations alter column payment_method set default 'paystack';

create index if not exists preorder_reservations_user_id_idx on public.preorder_reservations (user_id);

alter table public.preorder_reservations enable row level security;

-- Customers can see only their own reservations.
drop policy if exists "users can view their own reservations" on public.preorder_reservations;
create policy "users can view their own reservations" on public.preorder_reservations
  for select
  using (auth.uid() = user_id);

-- No client-side insert/update policy for regular users — writes only
-- happen through the Edge Function, which uses the service role key and
-- bypasses RLS entirely after verifying payment with Paystack.
drop policy if exists "users can create their own reservations" on public.preorder_reservations;

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

-- ---------- 4. Receipt storage (optional) ----------
-- No longer required now that Paystack verifies payments server-side —
-- receipt_path is nullable and unused by the Paystack flow. Keep this
-- section only if you still want a manual/offline payment fallback path
-- that an admin reviews by hand; otherwise it's safe to skip.
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
