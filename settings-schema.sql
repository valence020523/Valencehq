-- ============================================================
-- VALENCE — settings page support
-- Run this in the Supabase SQL editor.
-- ============================================================

-- Notification preference toggle used on settings.html.
alter table public.profiles add column if not exists email_notifications boolean not null default true;

-- Your profiles table should already have these from your original
-- handle_new_user setup, but re-running is harmless (drop + recreate)
-- and ensures settings.html can read/update the row.
alter table public.profiles enable row level security;

drop policy if exists "users can view their own profile" on public.profiles;
create policy "users can view their own profile" on public.profiles
  for select
  using (auth.uid() = id);

drop policy if exists "users can update their own profile" on public.profiles;
create policy "users can update their own profile" on public.profiles
  for update
  using (auth.uid() = id);
