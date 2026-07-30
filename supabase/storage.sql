-- Storage is applied after Supabase initializes its internal storage schema.
alter table if exists public.profiles
  add column if not exists verified boolean default false not null;

grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.tweets, public.likes, public.retweets, public.follows
  to anon, authenticated;
grant update on public.profiles to authenticated;
grant insert, delete on public.tweets, public.likes, public.retweets, public.follows
  to authenticated;
grant select, insert, delete on public.bookmarks to authenticated;
grant select, update on public.notifications to authenticated;
grant select, insert, update on public.messages to authenticated;
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_trends'
  ) then
    grant execute on function public.get_trends() to anon, authenticated;
  end if;
end $$;

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