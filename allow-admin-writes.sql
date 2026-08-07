-- Allow logged-in (authenticated) users to add products.
-- Public/anon visitors still only get read access (from the earlier policy).
create policy "Authenticated users can insert products"
  on products for insert
  to authenticated
  with check (true);

-- Optional: let logged-in users edit/delete too
create policy "Authenticated users can update products"
  on products for update
  to authenticated
  using (true);

create policy "Authenticated users can delete products"
  on products for delete
  to authenticated
  using (true);
