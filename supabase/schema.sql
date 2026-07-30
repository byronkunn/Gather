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

alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type = any (array['like'::text, 'retweet'::text, 'reply'::text, 'follow'::text, 'mention'::text, 'quote'::text, 'message'::text, 'message_request'::text, 'community'::text, 'announcement'::text]));

create or replace function public.can_view_tweet(target_tweet_id uuid, viewer_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.tweets t
    where t.id = target_tweet_id
      and t.deleted_at is null
      and (t.status = 'published' or t.user_id = viewer_id)
  );
$$;

create or replace function public.can_reply_to_tweet(target_tweet_id uuid, replier_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case
    when target_tweet_id is null then true
    else exists (
      select 1
      from public.tweets t
      where t.id = target_tweet_id
        and t.deleted_at is null
        and (
          t.reply_audience = 'everyone'
          or t.user_id = replier_id
          or (
            t.reply_audience = 'following'
            and exists (
              select 1
              from public.follows f
              where f.follower_id = replier_id
                and f.following_id = t.user_id
            )
          )
          or (
            t.reply_audience = 'mentioned'
            and exists (
              select 1
              from public.tweet_mentions tm
              where tm.tweet_id = t.id
                and tm.mentioned_user_id = replier_id
                and tm.removed_at is null
            )
          )
        )
    )
  end;
$$;

alter table public.tweets add column status text default 'published' not null;
alter table public.tweets add column quote_tweet_id uuid references public.tweets (id) on delete set null;
alter table public.tweets add column reply_audience text default 'everyone' not null;
alter table public.tweets add column sensitive boolean default false not null;
alter table public.tweets add column thread_root_id uuid references public.tweets (id) on delete set null;
alter table public.tweets add column thread_position integer default 0 not null;
alter table public.tweets add column language_code text;
alter table public.tweets add column edited_at timestamptz;
alter table public.tweets add column deleted_at timestamptz;
alter table public.tweets add constraint tweets_status_check check (status in ('draft', 'published'));
alter table public.tweets add constraint tweets_reply_audience_check check (reply_audience in ('everyone', 'following', 'mentioned'));
alter table public.tweets add constraint tweets_thread_position_check check (thread_position >= 0);
create index tweets_status_created_idx on public.tweets (status, created_at desc);
create index tweets_thread_root_idx on public.tweets (thread_root_id, thread_position);
create index tweets_quote_idx on public.tweets (quote_tweet_id);

create table public.tweet_media (
  id uuid primary key default gen_random_uuid(),
  tweet_id uuid not null references public.tweets (id) on delete cascade,
  type text not null check (type in ('image', 'video', 'gif', 'link')),
  url text not null,
  alt_text text,
  sensitive boolean default false not null,
  position smallint default 0 not null check (position >= 0),
  mime text,
  width integer,
  height integer,
  duration_ms integer,
  meta jsonb not null default '{}'::jsonb
);

create table public.tweet_media_tags (
  media_id uuid not null references public.tweet_media (id) on delete cascade,
  tagged_user_id uuid not null references public.profiles (id) on delete cascade,
  x numeric(5,2),
  y numeric(5,2),
  created_at timestamptz default now() not null,
  primary key (media_id, tagged_user_id)
);

create table public.tweet_hashtags (
  tweet_id uuid not null references public.tweets (id) on delete cascade,
  tag text not null,
  created_at timestamptz default now() not null,
  primary key (tweet_id, tag)
);

create table public.tweet_mentions (
  tweet_id uuid not null references public.tweets (id) on delete cascade,
  mentioned_user_id uuid not null references public.profiles (id) on delete cascade,
  mentioned_by_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now() not null,
  removed_at timestamptz,
  primary key (tweet_id, mentioned_user_id)
);

create table public.tweet_polls (
  tweet_id uuid primary key references public.tweets (id) on delete cascade,
  expires_at timestamptz not null,
  multiple_choice boolean default false not null,
  ended_at timestamptz,
  created_at timestamptz default now() not null
);

create table public.tweet_poll_options (
  id uuid primary key default gen_random_uuid(),
  tweet_id uuid not null references public.tweet_polls (tweet_id) on delete cascade,
  label text not null check (char_length(label) <= 25),
  position smallint not null,
  unique (tweet_id, position)
);

create table public.tweet_poll_votes (
  tweet_id uuid not null references public.tweet_polls (tweet_id) on delete cascade,
  option_id uuid not null references public.tweet_poll_options (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now() not null,
  primary key (option_id, user_id),
  unique (tweet_id, user_id)
);

create table public.tweet_conversation_mutes (
  tweet_id uuid not null references public.tweets (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  muted_at timestamptz default now() not null,
  primary key (tweet_id, user_id)
);

create table public.hidden_replies (
  tweet_id uuid not null references public.tweets (id) on delete cascade,
  hidden_reply_id uuid not null references public.tweets (id) on delete cascade,
  hidden_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now() not null,
  primary key (tweet_id, hidden_reply_id)
);

create table public.removed_mentions (
  tweet_id uuid not null references public.tweets (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now() not null,
  primary key (tweet_id, user_id)
);

create table public.account_mutes (
  muter_id uuid not null references public.profiles (id) on delete cascade,
  muted_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now() not null,
  expires_at timestamptz,
  primary key (muter_id, muted_id),
  check (muter_id <> muted_id)
);

create table public.muted_keywords (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  phrase text not null check (char_length(phrase) > 0),
  created_at timestamptz default now() not null,
  expires_at timestamptz
);

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  tweet_id uuid references public.tweets (id) on delete cascade,
  profile_id uuid references public.profiles (id) on delete cascade,
  message_id uuid references public.dm_messages (id) on delete cascade,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz default now() not null
);

create index tweet_media_tweet_idx on public.tweet_media (tweet_id, position);
create index tweet_hashtags_tag_idx on public.tweet_hashtags (tag);
create index tweet_mentions_user_idx on public.tweet_mentions (mentioned_user_id, created_at desc);

alter table public.tweet_media enable row level security;
alter table public.tweet_media_tags enable row level security;
alter table public.tweet_hashtags enable row level security;
alter table public.tweet_mentions enable row level security;
alter table public.tweet_polls enable row level security;
alter table public.tweet_poll_options enable row level security;
alter table public.tweet_poll_votes enable row level security;
alter table public.tweet_conversation_mutes enable row level security;
alter table public.hidden_replies enable row level security;
alter table public.removed_mentions enable row level security;
alter table public.account_mutes enable row level security;
alter table public.muted_keywords enable row level security;
alter table public.content_reports enable row level security;

grant update on public.tweets to authenticated;
grant select on public.tweet_media, public.tweet_media_tags, public.tweet_hashtags, public.tweet_mentions, public.tweet_polls, public.tweet_poll_options, public.tweet_poll_votes to anon, authenticated;
grant insert, update, delete on public.tweet_media, public.tweet_media_tags, public.tweet_hashtags, public.tweet_mentions, public.tweet_polls, public.tweet_poll_options to authenticated;
grant insert, delete on public.tweet_poll_votes to authenticated;
grant select, insert, delete on public.tweet_conversation_mutes, public.hidden_replies, public.removed_mentions, public.account_mutes to authenticated;
grant select, insert, update, delete on public.muted_keywords to authenticated;
grant select, insert on public.content_reports to authenticated;
grant execute on function public.can_view_tweet(uuid, uuid) to anon, authenticated;
grant execute on function public.can_reply_to_tweet(uuid, uuid) to authenticated;

drop policy "tweets viewable by everyone" on public.tweets;
drop policy "users insert own tweets" on public.tweets;
create policy "published tweets viewable by everyone" on public.tweets for select using (status = 'published' and deleted_at is null);
create policy "users view own tweets" on public.tweets for select using (auth.uid() = user_id);
create policy "users insert own tweets" on public.tweets for insert with check (auth.uid() = user_id and public.can_reply_to_tweet(reply_to, user_id));
create policy "users update own tweets" on public.tweets for update using (auth.uid() = user_id);

create policy "tweet media visible with tweet" on public.tweet_media for select using (public.can_view_tweet(tweet_id, auth.uid()));
create policy "tweet media owned by author" on public.tweet_media for insert with check (
  exists (
    select 1 from public.tweets t where t.id = tweet_media.tweet_id and t.user_id = auth.uid()
  )
);
create policy "tweet media author updates" on public.tweet_media for update using (
  exists (
    select 1 from public.tweets t where t.id = tweet_media.tweet_id and t.user_id = auth.uid()
  )
);
create policy "tweet media author deletes" on public.tweet_media for delete using (
  exists (
    select 1 from public.tweets t where t.id = tweet_media.tweet_id and t.user_id = auth.uid()
  )
);

create policy "tweet media tags visible with tweet" on public.tweet_media_tags for select using (
  exists (
    select 1
    from public.tweet_media tm
    join public.tweets t on t.id = tm.tweet_id
    where tm.id = tweet_media_tags.media_id
      and public.can_view_tweet(t.id, auth.uid())
  )
);
create policy "tweet media tags owned by author" on public.tweet_media_tags for insert with check (
  exists (
    select 1
    from public.tweet_media tm
    join public.tweets t on t.id = tm.tweet_id
    where tm.id = tweet_media_tags.media_id
      and t.user_id = auth.uid()
  )
);
create policy "tweet media tags author deletes" on public.tweet_media_tags for delete using (
  exists (
    select 1
    from public.tweet_media tm
    join public.tweets t on t.id = tm.tweet_id
    where tm.id = tweet_media_tags.media_id
      and t.user_id = auth.uid()
  )
);

create policy "hashtags viewable" on public.tweet_hashtags for select using (true);
create policy "authors manage hashtags" on public.tweet_hashtags for insert with check (
  exists (
    select 1 from public.tweets t where t.id = tweet_hashtags.tweet_id and t.user_id = auth.uid()
  )
);
create policy "authors delete hashtags" on public.tweet_hashtags for delete using (
  exists (
    select 1 from public.tweets t where t.id = tweet_hashtags.tweet_id and t.user_id = auth.uid()
  )
);

create policy "mentions visible to participant or public viewers" on public.tweet_mentions for select using (
  auth.uid() = mentioned_user_id or public.can_view_tweet(tweet_id, auth.uid())
);
create policy "authors create mentions" on public.tweet_mentions for insert with check (
  auth.uid() = mentioned_by_id and exists (
    select 1 from public.tweets t where t.id = tweet_mentions.tweet_id and t.user_id = auth.uid()
  )
);
create policy "authors update mentions" on public.tweet_mentions for update using (
  exists (
    select 1 from public.tweets t where t.id = tweet_mentions.tweet_id and t.user_id = auth.uid()
  )
);

create policy "polls visible with tweet" on public.tweet_polls for select using (public.can_view_tweet(tweet_id, auth.uid()));
create policy "authors manage polls" on public.tweet_polls for insert with check (
  exists (
    select 1 from public.tweets t where t.id = tweet_polls.tweet_id and t.user_id = auth.uid()
  )
);
create policy "authors update polls" on public.tweet_polls for update using (
  exists (
    select 1 from public.tweets t where t.id = tweet_polls.tweet_id and t.user_id = auth.uid()
  )
);
create policy "authors delete polls" on public.tweet_polls for delete using (
  exists (
    select 1 from public.tweets t where t.id = tweet_polls.tweet_id and t.user_id = auth.uid()
  )
);

create policy "poll options visible with tweet" on public.tweet_poll_options for select using (public.can_view_tweet(tweet_id, auth.uid()));
create policy "authors manage poll options" on public.tweet_poll_options for insert with check (
  exists (
    select 1 from public.tweets t where t.id = tweet_poll_options.tweet_id and t.user_id = auth.uid()
  )
);
create policy "authors update poll options" on public.tweet_poll_options for update using (
  exists (
    select 1 from public.tweets t where t.id = tweet_poll_options.tweet_id and t.user_id = auth.uid()
  )
);
create policy "authors delete poll options" on public.tweet_poll_options for delete using (
  exists (
    select 1 from public.tweets t where t.id = tweet_poll_options.tweet_id and t.user_id = auth.uid()
  )
);

create policy "poll votes visible with tweet" on public.tweet_poll_votes for select using (public.can_view_tweet(tweet_id, auth.uid()));
create policy "users vote as self" on public.tweet_poll_votes for insert with check (auth.uid() = user_id);
create policy "users retract own vote" on public.tweet_poll_votes for delete using (auth.uid() = user_id);

create policy "users manage own conversation mutes" on public.tweet_conversation_mutes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "authors manage hidden replies" on public.hidden_replies for select using (auth.uid() = hidden_by);
create policy "authors create hidden replies" on public.hidden_replies for insert with check (auth.uid() = hidden_by);
create policy "authors remove hidden replies" on public.hidden_replies for delete using (auth.uid() = hidden_by);
create policy "users manage removed mentions" on public.removed_mentions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "users manage account mutes" on public.account_mutes for all using (auth.uid() = muter_id) with check (auth.uid() = muter_id);
create policy "users manage muted keywords" on public.muted_keywords for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "users view own reports" on public.content_reports for select using (auth.uid() = reporter_id);
create policy "users create own reports" on public.content_reports for insert with check (auth.uid() = reporter_id);

alter publication supabase_realtime add table public.tweets;
alter publication supabase_realtime add table public.tweet_media;
alter publication supabase_realtime add table public.tweet_poll_votes;

