-- Storage is applied after Supabase initializes its internal storage schema.
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "media publicly readable" on storage.objects;
drop policy if exists "authed users upload media" on storage.objects;
drop policy if exists "users update own media" on storage.objects;
drop policy if exists "users delete own media" on storage.objects;

create policy "media publicly readable" on storage.objects
  for select using (bucket_id = 'media');
create policy "authed users upload media" on storage.objects
  for insert with check (bucket_id = 'media' and auth.role() = 'authenticated');
create policy "users update own media" on storage.objects
  for update using (bucket_id = 'media' and auth.uid() = owner);
create policy "users delete own media" on storage.objects
  for delete using (bucket_id = 'media' and auth.uid() = owner);