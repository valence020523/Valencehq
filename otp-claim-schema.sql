-- ============================================================
-- VALENCE — retailer OTP + customer self-claim schema
-- Run this in the Supabase SQL editor.
-- Assumes a `products` table already exists with at least:
--   qr_code text primary key (or unique),
--   item_number text,
--   owner_name text,
--   registered_at timestamptz
-- and that anon SELECT on `products` is already allowed
-- (product.html already relies on this).
-- ============================================================

-- ---------- 1. Retailers ----------
-- One row per retailer, keyed to their Supabase auth user id.
-- Add rows yourself (Supabase dashboard -> Authentication, create the
-- user, then insert a matching row here) — there's no public signup.
create table if not exists public.retailers (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.retailers enable row level security;

drop policy if exists "retailers can view own row" on public.retailers;
create policy "retailers can view own row" on public.retailers
  for select
  using (auth.uid() = id);

-- The admin (identified by email, matching ADMIN_EMAIL in verifyadmin.html)
-- can see, add, and update retailer rows from the admin panel. Keep this
-- email in sync with ADMIN_EMAIL in verifyadmin.html.
drop policy if exists "admin can view all retailers" on public.retailers;
create policy "admin can view all retailers" on public.retailers
  for select
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

drop policy if exists "admin can insert retailers" on public.retailers;
create policy "admin can insert retailers" on public.retailers
  for insert
  with check ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

drop policy if exists "admin can update retailers" on public.retailers;
create policy "admin can update retailers" on public.retailers
  for update
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

-- ---------- 2. OTP codes ----------
create table if not exists public.otp_codes (
  id bigint generated always as identity primary key,
  qr_code text not null references public.products(qr_code) on delete cascade,
  otp text not null,
  expires_at timestamptz not null,
  verified boolean not null default false,
  used boolean not null default false,
  created_by uuid references public.retailers(id),
  created_at timestamptz not null default now()
);

create index if not exists otp_codes_qr_code_idx on public.otp_codes (qr_code);

alter table public.otp_codes enable row level security;

-- Active retailers can create OTPs for any product.
drop policy if exists "active retailers can create otp" on public.otp_codes;
create policy "active retailers can create otp" on public.otp_codes
  for insert
  with check (
    created_by = auth.uid()
    and exists (select 1 from public.retailers r where r.id = auth.uid() and r.active)
  );

-- Retailers can see the OTPs they personally generated (e.g. to show a
-- "recently issued" list or re-render a countdown after a page refresh).
drop policy if exists "retailers can view own otps" on public.otp_codes;
create policy "retailers can view own otps" on public.otp_codes
  for select
  using (created_by = auth.uid());

-- Deliberately NO select/insert policy for anon. Customers never read this
-- table directly — they only interact with it through the RPC functions
-- below, so a valid OTP value is never exposed to the public.

-- ---------- 3. RPC: verify_otp ----------
-- Step 1 of the customer claim flow. Checks the code the customer typed
-- is correct, unused, and still inside its 30-second window, and marks it
-- "verified" so the customer has more time to fill in serial + name next
-- without racing the 30-second clock.
create or replace function public.verify_otp(
  p_qr_code text,
  p_otp text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  select * into v_row
    from otp_codes
    where qr_code = p_qr_code
      and otp = p_otp
      and used = false
    order by created_at desc
    limit 1;

  if v_row is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_otp');
  end if;

  if v_row.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'expired_otp');
  end if;

  update otp_codes set verified = true where id = v_row.id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.verify_otp(text, text) to anon, authenticated;

-- ---------- 4. RPC: claim_product ----------
-- Step 2 of the customer claim flow. Requires an already-verified OTP for
-- this qr_code, cross-checks the serial (item_number) the customer typed
-- against the one on file, then writes owner_name + registered_at and
-- burns the OTP. Runs as one atomic transaction.
create or replace function public.claim_product(
  p_qr_code text,
  p_otp text,
  p_item_number text,
  p_owner_name text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product record;
  v_otp record;
begin
  if coalesce(trim(p_owner_name), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_name');
  end if;

  select * into v_product from products where qr_code = p_qr_code;

  if v_product is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_product.owner_name is not null and v_product.owner_name <> '' then
    return jsonb_build_object('ok', false, 'error', 'already_registered');
  end if;

  select * into v_otp
    from otp_codes
    where qr_code = p_qr_code
      and otp = p_otp
      and verified = true
      and used = false
    order by created_at desc
    limit 1;

  if v_otp is null then
    return jsonb_build_object('ok', false, 'error', 'otp_not_verified');
  end if;

  if v_product.item_number is not null and v_product.item_number <> ''
     and trim(p_item_number) <> v_product.item_number then
    return jsonb_build_object('ok', false, 'error', 'serial_mismatch');
  end if;

  update otp_codes set used = true where id = v_otp.id;

  update products
    set owner_name = trim(p_owner_name),
        registered_at = now()
    where qr_code = p_qr_code;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.claim_product(text, text, text, text) to anon, authenticated;

-- ---------- 5. Housekeeping ----------
-- Optional: periodically delete old/expired/used OTPs. You can run this
-- manually, or wire it to a Supabase cron job (pg_cron) if you have it
-- enabled.
-- delete from otp_codes where used = true or expires_at < now() - interval '1 day';
