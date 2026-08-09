-- ============================================================
-- VALENCE — split preorder_listings between Pre-Order and Explore Market
-- Run this in the Supabase SQL editor.
-- ============================================================

-- listing_type distinguishes which surface a listing appears on:
--   'preorder' -> shows on preorder.html, with the deposit/Paystack flow
--   'market'   -> shows on market.html, browse-only (no purchase flow)
-- Existing rows default to 'preorder' so nothing already live moves.
alter table public.preorder_listings
  add column if not exists listing_type text not null default 'preorder';

alter table public.preorder_listings
  drop constraint if exists preorder_listings_listing_type_check;
alter table public.preorder_listings
  add constraint preorder_listings_listing_type_check
  check (listing_type in ('preorder', 'market'));

create index if not exists preorder_listings_type_idx on public.preorder_listings (listing_type);
