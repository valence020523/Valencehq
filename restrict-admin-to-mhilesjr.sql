-- Remove the broader "any authenticated user" policies from before, if you ran them
drop policy if exists "Authenticated users can insert products" on products;
drop policy if exists "Authenticated users can update products" on products;
drop policy if exists "Authenticated users can delete products" on products;

-- Only mhilesjr@gmail.com may insert/update/delete products.
-- Public/anon read access (from the first policy) is unaffected.
create policy "Only mhilesjr can insert products"
  on products for insert
  to authenticated
  with check (auth.jwt() ->> 'email' = 'mhilesjr@gmail.com');

create policy "Only mhilesjr can update products"
  on products for update
  to authenticated
  using (auth.jwt() ->> 'email' = 'mhilesjr@gmail.com');

create policy "Only mhilesjr can delete products"
  on products for delete
  to authenticated
  using (auth.jwt() ->> 'email' = 'mhilesjr@gmail.com');
