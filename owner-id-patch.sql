-- ============================================================
-- VALENCE — link claimed products to the authenticated account
-- Run this in the Supabase SQL editor AFTER otp-claim-schema.sql.
-- ============================================================

-- ---------- 1. Add owner_id to products ----------
-- Stores the auth.users id of whoever claimed the item, alongside the
-- existing free-text owner_name. This is what My Collection filters on.
alter table public.products add column if not exists owner_id uuid references auth.users(id);

create index if not exists products_owner_id_idx on public.products (owner_id);

-- Customers need to be able to see their own claimed products for
-- My Collection. (Skip this if anon/authenticated SELECT on products is
-- already unrestricted, as the comments in otp-claim-schema.sql suggest —
-- in that case this policy is redundant but harmless.)
drop policy if exists "owners can view their own products" on public.products;
create policy "owners can view their own products" on public.products
  for select
  using (auth.uid() = owner_id);

-- ---------- 2. Patch claim_product to stamp owner_id ----------
-- Same logic as before, but now requires the caller to be logged in
-- (auth.uid() is read from the request's JWT — works correctly inside a
-- SECURITY DEFINER function since it reflects the caller, not the
-- function's owner) and writes owner_id alongside owner_name.
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
  v_expected_serial text;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_logged_in');
  end if;

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

  v_expected_serial := nullif(v_product.serial_number, '');
  if v_expected_serial is null then
    v_expected_serial := nullif(v_product.item_number, '');
  end if;

  if v_expected_serial is not null and trim(p_item_number) <> v_expected_serial then
    return jsonb_build_object('ok', false, 'error', 'serial_mismatch');
  end if;

  update otp_codes set used = true where id = v_otp.id;

  update products
    set owner_name = trim(p_owner_name),
        owner_id = v_uid,
        registered_at = now()
    where qr_code = p_qr_code;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.claim_product(text, text, text, text) to anon, authenticated;
