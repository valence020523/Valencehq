-- ============================================================
-- VALENCE — run this once in the Supabase SQL editor
-- Creates a `profiles` table that mirrors each auth user and
-- enforces uniqueness on username / phone / email so the signup
-- form can check availability and reject duplicates.
-- ============================================================

create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  username   text not null unique,
  email      text not null unique,
  phone      text not null unique,
  created_at timestamptz not null default now()
);

-- Case-insensitive uniqueness for username/email as well
create unique index if not exists profiles_username_lower_idx on public.profiles (lower(username));
create unique index if not exists profiles_email_lower_idx    on public.profiles (lower(email));

alter table public.profiles enable row level security;

-- Anyone (including anon, pre-login) can read ONLY the columns needed
-- to check availability during signup. We expose a narrow view instead
-- of the raw table so passwords/ids etc. are never exposed.
create or replace view public.profile_lookup as
  select username, email, phone from public.profiles;

grant select on public.profile_lookup to anon, authenticated;

-- Users can read/update only their own row.
create policy "profiles: select own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles: update own" on public.profiles
  for update using (auth.uid() = id);

-- Auto-create the profile row right after a user confirms/signs up,
-- pulling username/phone out of the signUp() `options.data` metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, email, phone)
  values (
    new.id,
    new.raw_user_meta_data->>'username',
    new.email,
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
