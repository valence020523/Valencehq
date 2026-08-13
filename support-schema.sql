-- ============================================================
-- VALENCE — support tickets
-- Run this in the Supabase SQL editor.
-- ============================================================

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null,
  message text not null,
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  created_at timestamptz not null default now()
);

create index if not exists support_tickets_user_id_idx on public.support_tickets (user_id);

alter table public.support_tickets enable row level security;

-- Customers can see and create only their own tickets.
drop policy if exists "users can view their own tickets" on public.support_tickets;
create policy "users can view their own tickets" on public.support_tickets
  for select
  using (auth.uid() = user_id);

drop policy if exists "users can create their own tickets" on public.support_tickets;
create policy "users can create their own tickets" on public.support_tickets
  for insert
  with check (auth.uid() = user_id);

-- Admin can see and update every ticket (e.g. change status as they work
-- through it). No admin UI built yet — update status by hand in the Table
-- Editor for now, or ask to have a support admin page built.
drop policy if exists "admin can view all tickets" on public.support_tickets;
create policy "admin can view all tickets" on public.support_tickets
  for select
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

drop policy if exists "admin can update tickets" on public.support_tickets;
create policy "admin can update tickets" on public.support_tickets
  for update
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');
