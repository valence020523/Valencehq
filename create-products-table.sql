-- Table backing the "Verify Authenticity" QR scanner
create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  qr_code text not null unique,
  product_name text,
  batch_number text,
  manufactured_at date,
  created_at timestamptz not null default now()
);

create index if not exists products_qr_code_idx on products (qr_code);

-- Row Level Security: the verify page uses the public anon key,
-- so allow anonymous READ only. No insert/update/delete from the client.
alter table products enable row level security;

create policy "Public can read products"
  on products for select
  to anon
  using (true);

-- Example row for testing the scanner end-to-end
insert into products (qr_code, product_name, batch_number, manufactured_at)
values ('VALENCE-TEST-0001', 'Sample Item', 'BATCH-2026-01', '2026-01-15')
on conflict (qr_code) do nothing;
