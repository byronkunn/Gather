-- ============================================================
-- Gather local Supabase schema
-- Applied by `supabase db reset` through supabase/config.toml.
-- ============================================================

-- ---------- TABLES ----------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique not null,
  display_name text not null,
  verified boolean default false not null,
  is_protected boolean default false not null,
  dm_allow_from text default 'following' not null check (dm_allow_from in ('following', 'verified', 'anyone', 'previous')),
  allow_calls_from text default 'following' not null check (allow_calls_from in ('following', 'verified', 'anyone', 'previous')),
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

alter table public.profiles
  add column pinned_tweet_id uuid references public.tweets (id) on delete set null;

create table public.follow_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz default now() not null,
  unique (requester_id, target_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'direct' check (kind in ('direct', 'group')),
  title text,
  image_url text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now() not null
);

create table public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  reply_to_message_id uuid references public.dm_messages (id) on delete set null,
  content text not null check (char_length(content) <= 2000),
  kind text not null default 'text' check (kind in ('text', 'shared_post', 'system')),
  created_at timestamptz default now() not null
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz default now() not null,
  muted_until timestamptz,
  last_read_message_id uuid references public.dm_messages (id) on delete set null,
  deleted_at timestamptz,
  primary key (conversation_id, user_id)
);

create table public.dm_message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.dm_messages (id) on delete cascade,
  type text not null check (type in ('image', 'video', 'gif', 'file', 'link')),
  url text not null,
  mime text,
  size_bytes bigint,
  meta jsonb not null default '{}'::jsonb
);

create table public.dm_message_reactions (
  message_id uuid not null references public.dm_messages (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  emoji text not null,
  created_at timestamptz default now() not null,
  primary key (message_id, user_id, emoji)
);

create table public.dm_message_receipts (
  message_id uuid not null references public.dm_messages (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null check (status in ('sent', 'delivered', 'read', 'failed')),
  updated_at timestamptz default now() not null,
  primary key (message_id, user_id)
);

create table public.dm_conversation_requests (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null unique references public.conversations (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  requester_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'deleted', 'blocked', 'reported')),
  created_at timestamptz default now() not null,
  reviewed_at timestamptz
);

create table public.dm_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  conversation_id uuid references public.conversations (id) on delete cascade,
  message_id uuid references public.dm_messages (id) on delete cascade,
  reason text not null,
  created_at timestamptz default now() not null
);

create table public.dm_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now() not null,
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index tweets_user_idx on public.tweets (user_id, created_at desc);
create index tweets_reply_idx on public.tweets (reply_to);
create index tweets_created_idx on public.tweets (created_at desc);
create index notif_user_idx on public.notifications (user_id, created_at desc);
create index msg_pair_idx on public.messages (sender_id, recipient_id, created_at desc);
create index follows_following_idx on public.follows (following_id);
create index follow_requests_target_idx on public.follow_requests (target_id, status, created_at desc);
create index conv_member_user_idx on public.conversation_members (user_id, joined_at desc);
create index dm_msg_conv_created_idx on public.dm_messages (conversation_id, created_at desc);
create index dm_request_recipient_idx on public.dm_conversation_requests (recipient_id, status, created_at desc);
create index dm_receipt_user_idx on public.dm_message_receipts (user_id, status, updated_at desc);

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
alter table public.follow_requests enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.dm_messages enable row level security;
alter table public.dm_message_attachments enable row level security;
alter table public.dm_message_reactions enable row level security;
alter table public.dm_message_receipts enable row level security;
alter table public.dm_conversation_requests enable row level security;
alter table public.dm_reports enable row level security;
alter table public.dm_blocks enable row level security;

-- ---------- API GRANTS ----------

grant usage on schema public to anon, authenticated;

grant select on public.profiles, public.tweets, public.likes, public.retweets, public.follows
  to anon, authenticated;
grant update on public.profiles to authenticated;
grant insert, delete on public.tweets, public.likes, public.retweets, public.follows
  to authenticated;
grant select, insert, delete on public.bookmarks to authenticated;
grant select, update on public.notifications to authenticated;
grant select, insert, update on public.messages to authenticated;
grant select, insert, update, delete on public.follow_requests to authenticated;
grant select, insert, update, delete on public.conversations to authenticated;
grant select, insert, update, delete on public.conversation_members to authenticated;
grant select, insert, update, delete on public.dm_messages to authenticated;
grant select, insert, update, delete on public.dm_message_attachments to authenticated;
grant select, insert, delete on public.dm_message_reactions to authenticated;
grant select, insert, update on public.dm_message_receipts to authenticated;
grant select, insert, update on public.dm_conversation_requests to authenticated;
grant select, insert on public.dm_reports to authenticated;
grant select, insert, delete on public.dm_blocks to authenticated;
grant execute on function public.get_trends() to anon, authenticated;

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

create policy "follow request visible to requester or target" on public.follow_requests
  for select using (auth.uid() = requester_id or auth.uid() = target_id);
create policy "create own follow request" on public.follow_requests
  for insert with check (auth.uid() = requester_id);
create policy "target updates follow request" on public.follow_requests
  for update using (auth.uid() = target_id);

create policy "members see conversations" on public.conversations
  for select using (
    exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = conversations.id
        and cm.user_id = auth.uid()
        and cm.deleted_at is null
    )
  );
create policy "create conversation as self" on public.conversations
  for insert with check (auth.uid() = created_by);

create policy "members see conversation members" on public.conversation_members
  for select using (
    exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = conversation_members.conversation_id
        and cm.user_id = auth.uid()
        and cm.deleted_at is null
    )
  );
create policy "members update own conversation state" on public.conversation_members
  for update using (auth.uid() = user_id);

create policy "members see dm messages" on public.dm_messages
  for select using (
    exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = dm_messages.conversation_id
        and cm.user_id = auth.uid()
        and cm.deleted_at is null
    )
  );
create policy "members send dm messages" on public.dm_messages
  for insert with check (
    auth.uid() = sender_id
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = dm_messages.conversation_id
        and cm.user_id = auth.uid()
        and cm.deleted_at is null
    )
  );

create policy "members see dm attachments" on public.dm_message_attachments
  for select using (
    exists (
      select 1
      from public.dm_messages m
      join public.conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = dm_message_attachments.message_id
        and cm.user_id = auth.uid()
        and cm.deleted_at is null
    )
  );
create policy "sender inserts dm attachments" on public.dm_message_attachments
  for insert with check (
    exists (
      select 1
      from public.dm_messages m
      where m.id = dm_message_attachments.message_id
        and m.sender_id = auth.uid()
    )
  );

create policy "members see dm reactions" on public.dm_message_reactions
  for select using (
    exists (
      select 1
      from public.dm_messages m
      join public.conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = dm_message_reactions.message_id
        and cm.user_id = auth.uid()
        and cm.deleted_at is null
    )
  );
create policy "react as self" on public.dm_message_reactions
  for insert with check (auth.uid() = user_id);
create policy "remove own reaction" on public.dm_message_reactions
  for delete using (auth.uid() = user_id);

create policy "member sees own receipts" on public.dm_message_receipts
  for select using (auth.uid() = user_id);
create policy "member inserts own receipts" on public.dm_message_receipts
  for insert with check (auth.uid() = user_id);
create policy "member updates own receipts" on public.dm_message_receipts
  for update using (auth.uid() = user_id);

create policy "recipient or requester sees requests" on public.dm_conversation_requests
  for select using (auth.uid() = recipient_id or auth.uid() = requester_id);
create policy "requester creates request" on public.dm_conversation_requests
  for insert with check (auth.uid() = requester_id);
create policy "recipient resolves request" on public.dm_conversation_requests
  for update using (auth.uid() = recipient_id);

create policy "report as self" on public.dm_reports
  for insert with check (auth.uid() = reporter_id);

create policy "see own dm blocks" on public.dm_blocks
  for select using (auth.uid() = blocker_id);
create policy "create own dm block" on public.dm_blocks
  for insert with check (auth.uid() = blocker_id);
create policy "remove own dm block" on public.dm_blocks
  for delete using (auth.uid() = blocker_id);

-- ---------- REALTIME ----------
-- Enable realtime for messages + notifications
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.dm_messages;
alter publication supabase_realtime add table public.dm_conversation_requests;

