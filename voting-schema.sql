-- ============================================================
-- VALENCE — community voting
-- Run this in the Supabase SQL editor.
-- ============================================================

create table if not exists public.voting_polls (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  image_url text,
  -- e.g. '[{"id":"a","label":"Design A"},{"id":"b","label":"Design B"}]'
  options jsonb not null,
  active boolean not null default true,
  closes_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.voting_polls enable row level security;

drop policy if exists "authenticated can view active polls" on public.voting_polls;
create policy "authenticated can view active polls" on public.voting_polls
  for select
  using (active = true);

-- Admin can manage polls. Add an admin UI later, or add/edit rows by hand
-- in the Table Editor for now.
drop policy if exists "admin can manage polls" on public.voting_polls;
create policy "admin can manage polls" on public.voting_polls
  for all
  using ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'mhilesjr@gmail.com');

create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.voting_polls(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  option_id text not null,
  created_at timestamptz not null default now(),
  unique (poll_id, user_id) -- one vote per person per poll
);

create index if not exists poll_votes_poll_id_idx on public.poll_votes (poll_id);

alter table public.poll_votes enable row level security;

drop policy if exists "users can view their own votes" on public.poll_votes;
create policy "users can view their own votes" on public.poll_votes
  for select
  using (auth.uid() = user_id);

drop policy if exists "users can cast their own vote" on public.poll_votes;
create policy "users can cast their own vote" on public.poll_votes
  for insert
  with check (auth.uid() = user_id);

-- Aggregate vote counts per option. Runs with the view owner's privileges
-- (standard Postgres view behavior), so it can count across all users
-- without exposing who voted for what — voting.html only ever reads
-- totals from here, never raw poll_votes rows belonging to other people.
create or replace view public.poll_option_counts as
select poll_id, option_id, count(*) as vote_count
from public.poll_votes
group by poll_id, option_id;

grant select on public.poll_option_counts to authenticated;
