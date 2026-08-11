-- ============================================================
-- VALENCE — orders (Buy Now purchases) with address + tracking
-- Run this in the Supabase SQL editor.
-- ============================================================

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.preorder_listings(id) on delete cascade,

  -- Who it's shipping to (captured at checkout, not pulled from a saved
  -- profile, so it can differ from the account's own address).
  full_name text not null,
  phone text not null,
  address_line1 text not null,
  address_line2 text,
  city text not null,
  state text not null,
  postal_code text,
  country text not null default 'Nigeria',

  amount_paid_cents integer not null, -- kobo (₦1 = 100 kobo)
  payment_method text not null default 'paystack',
  paystack_reference text unique,

  -- Tracking
  tracking_number text unique not null,
  status text not null default 'paid'
    check (status in ('paid', 'processing', 'shipped', 'delivered', 'cancelled')),
  carrier text,
  tracking_url text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists orders_user_id_idx on public.orders (user_id);
create index if not exists orders_tracking_number_idx on public.orders (tracking_number);

alter table public.orders enable row level security;

-- Customers can see only their own orders.
drop policy if exists "users can view their own orders" on public.orders;
create policy "users can view their own orders" on public.orders
  for select
  using (auth.uid() = user_id);

-- No client-side insert/update policy — orders are created only by the
-- verify-order-payment Edge Function (service role, after confirming
-- payment with Paystack directly), same pattern as preorder_reservations.

-- Admin (keep in sync with ADMIN_EMAIL in your admin pages) can view and
-- update every order, e.g. to advance status and add tracking info.
drop policy if exists "admin can view all orders" on public.orders;
create policy "admin can view all orders" on public.orders
  for select
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

drop policy if exists "admin can update orders" on public.orders;
create policy "admin can update orders" on public.orders
  for update
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

-- Keep updated_at current on every change.
create or replace function public.set_orders_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
  before update on public.orders
  for each row
  execute function public.set_orders_updated_at();
