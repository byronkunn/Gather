-- ============================================================
-- Twitter Clone — Supabase schema
-- Run this whole file in: Supabase Dashboard -> SQL Editor
-- ============================================================

-- ---------- TABLES ----------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique not null,
  display_name text not null,
  bio text default '',
  location text default '',
  website text default '',
  avatar_url text,
  cover_url text,
  created_at timestamptz default now() not null
);

create table public.tweets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade not null,
  content text not null check (char_length(content) <= 280),
  image_url text,
  reply_to uuid references public.tweets (id) on delete cascade,
  created_at timestamptz default now() not null
);

create table public.likes (
  user_id uuid references public.profiles (id) on delete cascade not null,
  tweet_id uuid references public.tweets (id) on delete cascade not null,
  created_at timestamptz default now() not null,
  primary key (user_id, tweet_id)
);

create table public.retweets (
  user_id uuid references public.profiles (id) on delete cascade not null,
  tweet_id uuid references public.tweets (id) on delete cascade not null,
  created_at timestamptz default now() not null,
  primary key (user_id, tweet_id)
);

create table public.bookmarks (
  user_id uuid references public.profiles (id) on delete cascade not null,
  tweet_id uuid references public.tweets (id) on delete cascade not null,
  created_at timestamptz default now() not null,
  primary key (user_id, tweet_id)
);

create table public.follows (
  follower_id uuid references public.profiles (id) on delete cascade not null,
  following_id uuid references public.profiles (id) on delete cascade not null,
  created_at timestamptz default now() not null,
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade not null, -- recipient
  actor_id uuid references public.profiles (id) on delete cascade not null,
  type text not null check (type in ('like', 'retweet', 'reply', 'follow')),
  tweet_id uuid references public.tweets (id) on delete cascade,
  read boolean default false not null,
  created_at timestamptz default now() not null
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references public.profiles (id) on delete cascade not null,
  recipient_id uuid references public.profiles (id) on delete cascade not null,
  content text not null check (char_length(content) <= 1000),
  read boolean default false not null,
  created_at timestamptz default now() not null
);

create index tweets_user_idx on public.tweets (user_id, created_at desc);
create index tweets_reply_idx on public.tweets (reply_to);
create index tweets_created_idx on public.tweets (created_at desc);
create index notif_user_idx on public.notifications (user_id, created_at desc);
create index msg_pair_idx on public.messages (sender_id, recipient_id, created_at desc);
create index follows_following_idx on public.follows (following_id);

-- ---------- AUTO-CREATE PROFILE ON SIGNUP ----------

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', 'user_' || substr(new.id::text, 1, 8)),
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- NOTIFICATION TRIGGERS ----------

create or replace function public.notify_on_like()
returns trigger language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  select user_id into owner from tweets where id = new.tweet_id;
  if owner is not null and owner <> new.user_id then
    insert into notifications (user_id, actor_id, type, tweet_id)
    values (owner, new.user_id, 'like', new.tweet_id);
  end if;
  return new;
end; $$;

create trigger on_like after insert on public.likes
  for each row execute function public.notify_on_like();

create or replace function public.notify_on_retweet()
returns trigger language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  select user_id into owner from tweets where id = new.tweet_id;
  if owner is not null and owner <> new.user_id then
    insert into notifications (user_id, actor_id, type, tweet_id)
    values (owner, new.user_id, 'retweet', new.tweet_id);
  end if;
  return new;
end; $$;

create trigger on_retweet after insert on public.retweets
  for each row execute function public.notify_on_retweet();

create or replace function public.notify_on_reply()
returns trigger language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  if new.reply_to is not null then
    select user_id into owner from tweets where id = new.reply_to;
    if owner is not null and owner <> new.user_id then
      insert into notifications (user_id, actor_id, type, tweet_id)
      values (owner, new.user_id, 'reply', new.id);
    end if;
  end if;
  return new;
end; $$;

create trigger on_reply after insert on public.tweets
  for each row execute function public.notify_on_reply();

create or replace function public.notify_on_follow()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, actor_id, type)
  values (new.following_id, new.follower_id, 'follow');
  return new;
end; $$;

create trigger on_follow after insert on public.follows
  for each row execute function public.notify_on_follow();

-- ---------- TRENDS RPC ----------

create or replace function public.get_trends()
returns table (tag text, tweet_count bigint)
language sql stable
as $$
  select lower(m[1]) as tag, count(*) as tweet_count
  from public.tweets, lateral regexp_matches(content, '#(\w+)', 'g') as m
  where created_at > now() - interval '7 days'
  group by 1
  order by 2 desc
  limit 10;
$$;

-- ---------- ROW LEVEL SECURITY ----------

alter table public.profiles enable row level security;
alter table public.tweets enable row level security;
alter table public.likes enable row level security;
alter table public.retweets enable row level security;
alter table public.bookmarks enable row level security;
alter table public.follows enable row level security;
alter table public.notifications enable row level security;
alter table public.messages enable row level security;

-- profiles: public read, owner update
create policy "profiles are viewable by everyone" on public.profiles for select using (true);
create policy "users update own profile" on public.profiles for update using (auth.uid() = id);

-- tweets: public read, authed insert own, owner delete
create policy "tweets viewable by everyone" on public.tweets for select using (true);
create policy "users insert own tweets" on public.tweets for insert with check (auth.uid() = user_id);
create policy "users delete own tweets" on public.tweets for delete using (auth.uid() = user_id);

-- likes / retweets / follows: public read, own insert/delete
create policy "likes viewable" on public.likes for select using (true);
create policy "insert own like" on public.likes for insert with check (auth.uid() = user_id);
create policy "delete own like" on public.likes for delete using (auth.uid() = user_id);

create policy "retweets viewable" on public.retweets for select using (true);
create policy "insert own retweet" on public.retweets for insert with check (auth.uid() = user_id);
create policy "delete own retweet" on public.retweets for delete using (auth.uid() = user_id);

create policy "follows viewable" on public.follows for select using (true);
create policy "insert own follow" on public.follows for insert with check (auth.uid() = follower_id);
create policy "delete own follow" on public.follows for delete using (auth.uid() = follower_id);

-- bookmarks: private to owner
create policy "own bookmarks viewable" on public.bookmarks for select using (auth.uid() = user_id);
create policy "insert own bookmark" on public.bookmarks for insert with check (auth.uid() = user_id);
create policy "delete own bookmark" on public.bookmarks for delete using (auth.uid() = user_id);

-- notifications: recipient only (inserts happen via security-definer triggers)
create policy "own notifications viewable" on public.notifications for select using (auth.uid() = user_id);
create policy "mark own notifications read" on public.notifications for update using (auth.uid() = user_id);

-- messages: only sender/recipient
create policy "own messages viewable" on public.messages
  for select using (auth.uid() = sender_id or auth.uid() = recipient_id);
create policy "send messages as self" on public.messages
  for insert with check (auth.uid() = sender_id);
create policy "recipient marks read" on public.messages
  for update using (auth.uid() = recipient_id);

-- ---------- REALTIME ----------
-- Enable realtime for messages + notifications
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.notifications;

-- ---------- STORAGE ----------
-- Public bucket for avatars, covers, and tweet images
insert into storage.buckets (id, name, public) values ('media', 'media', true);

create policy "media publicly readable" on storage.objects
  for select using (bucket_id = 'media');
create policy "authed users upload media" on storage.objects
  for insert with check (bucket_id = 'media' and auth.role() = 'authenticated');
create policy "users update own media" on storage.objects
  for update using (bucket_id = 'media' and auth.uid() = owner);
create policy "users delete own media" on storage.objects
  for delete using (bucket_id = 'media' and auth.uid() = owner);
