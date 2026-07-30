SET check_function_bodies = false;
CREATE FUNCTION public.get_trends()
 RETURNS TABLE(tag text, tweet_count bigint)
 LANGUAGE sql
 STABLE
AS $function$
  select lower(m[1]) as tag, count(*) as tweet_count
  from public.tweets, lateral regexp_matches(content, '#(\w+)', 'g') as m
  where created_at > now() - interval '7 days'
  group by 1
  order by 2 desc
  limit 10;
$function$;
CREATE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', 'user_' || substr(new.id::text, 1, 8)),
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$function$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
CREATE FUNCTION public.notify_on_follow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into notifications (user_id, actor_id, type)
  values (new.following_id, new.follower_id, 'follow');
  return new;
end; $function$;
CREATE FUNCTION public.notify_on_like()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare owner uuid;
begin
  select user_id into owner from tweets where id = new.tweet_id;
  if owner is not null and owner <> new.user_id then
    insert into notifications (user_id, actor_id, type, tweet_id)
    values (owner, new.user_id, 'like', new.tweet_id);
  end if;
  return new;
end; $function$;
CREATE FUNCTION public.notify_on_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end; $function$;
CREATE FUNCTION public.notify_on_retweet()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare owner uuid;
begin
  select user_id into owner from tweets where id = new.tweet_id;
  if owner is not null and owner <> new.user_id then
    insert into notifications (user_id, actor_id, type, tweet_id)
    values (owner, new.user_id, 'retweet', new.tweet_id);
  end if;
  return new;
end; $function$;
CREATE TABLE public.bookmarks (user_id uuid NOT NULL, tweet_id uuid NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.bookmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookmarks ADD CONSTRAINT bookmarks_pkey PRIMARY KEY (user_id, tweet_id);
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.bookmarks TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.bookmarks TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.bookmarks TO service_role;
CREATE POLICY "delete own bookmark" ON public.bookmarks FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY "insert own bookmark" ON public.bookmarks FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "own bookmarks viewable" ON public.bookmarks FOR SELECT USING ((auth.uid() = user_id));
CREATE TABLE public.follows (follower_id uuid NOT NULL, following_id uuid NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ADD CONSTRAINT follows_check CHECK (follower_id <> following_id);
ALTER TABLE public.follows ADD CONSTRAINT follows_pkey PRIMARY KEY (follower_id, following_id);
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.follows TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.follows TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.follows TO service_role;
CREATE INDEX follows_following_idx ON public.follows (following_id);
CREATE TRIGGER on_follow AFTER INSERT ON public.follows FOR EACH ROW EXECUTE FUNCTION public.notify_on_follow();
CREATE POLICY "delete own follow" ON public.follows FOR DELETE USING ((auth.uid() = follower_id));
CREATE POLICY "follows viewable" ON public.follows FOR SELECT USING (true);
CREATE POLICY "insert own follow" ON public.follows FOR INSERT WITH CHECK ((auth.uid() = follower_id));
CREATE TABLE public.likes (user_id uuid NOT NULL, tweet_id uuid NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes ADD CONSTRAINT likes_pkey PRIMARY KEY (user_id, tweet_id);
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.likes TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.likes TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.likes TO service_role;
CREATE TRIGGER on_like AFTER INSERT ON public.likes FOR EACH ROW EXECUTE FUNCTION public.notify_on_like();
CREATE POLICY "delete own like" ON public.likes FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY "insert own like" ON public.likes FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "likes viewable" ON public.likes FOR SELECT USING (true);
CREATE TABLE public.messages (id uuid DEFAULT gen_random_uuid() NOT NULL, sender_id uuid NOT NULL, recipient_id uuid NOT NULL, content text NOT NULL, read boolean DEFAULT false NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ADD CONSTRAINT messages_content_check CHECK (char_length(content) <= 1000);
ALTER TABLE public.messages ADD CONSTRAINT messages_pkey PRIMARY KEY (id);
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.messages TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.messages TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.messages TO service_role;
CREATE INDEX msg_pair_idx ON public.messages (sender_id, recipient_id, created_at DESC);
CREATE POLICY "own messages viewable" ON public.messages FOR SELECT USING (((auth.uid() = sender_id) OR (auth.uid() = recipient_id)));
CREATE POLICY "recipient marks read" ON public.messages FOR UPDATE USING ((auth.uid() = recipient_id));
CREATE POLICY "send messages as self" ON public.messages FOR INSERT WITH CHECK ((auth.uid() = sender_id));
CREATE TABLE public.notifications (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, actor_id uuid NOT NULL, type text NOT NULL, tweet_id uuid, read boolean DEFAULT false NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages, TABLE public.notifications;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY['like'::text, 'retweet'::text, 'reply'::text, 'follow'::text]));
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.notifications TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.notifications TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.notifications TO service_role;
CREATE INDEX notif_user_idx ON public.notifications (user_id, created_at DESC);
CREATE POLICY "mark own notifications read" ON public.notifications FOR UPDATE USING ((auth.uid() = user_id));
CREATE POLICY "own notifications viewable" ON public.notifications FOR SELECT USING ((auth.uid() = user_id));
CREATE TABLE public.profiles (id uuid NOT NULL, username text NOT NULL, display_name text NOT NULL, bio text DEFAULT ''::text, location text DEFAULT ''::text, website text DEFAULT ''::text, avatar_url text, cover_url text, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
ALTER TABLE public.bookmarks ADD CONSTRAINT bookmarks_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.follows ADD CONSTRAINT follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.follows ADD CONSTRAINT follows_following_id_fkey FOREIGN KEY (following_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.likes ADD CONSTRAINT likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT messages_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_username_key UNIQUE (username);
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.profiles TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.profiles TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.profiles TO service_role;
CREATE POLICY "profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE USING ((auth.uid() = id));
CREATE TABLE public.retweets (user_id uuid NOT NULL, tweet_id uuid NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.retweets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.retweets ADD CONSTRAINT retweets_pkey PRIMARY KEY (user_id, tweet_id);
ALTER TABLE public.retweets ADD CONSTRAINT retweets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.retweets TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.retweets TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.retweets TO service_role;
CREATE TRIGGER on_retweet AFTER INSERT ON public.retweets FOR EACH ROW EXECUTE FUNCTION public.notify_on_retweet();
CREATE POLICY "delete own retweet" ON public.retweets FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY "insert own retweet" ON public.retweets FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "retweets viewable" ON public.retweets FOR SELECT USING (true);
CREATE TABLE public.tweets (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, content text NOT NULL, image_url text, reply_to uuid, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.tweets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tweets ADD CONSTRAINT tweets_content_check CHECK (char_length(content) <= 280);
ALTER TABLE public.tweets ADD CONSTRAINT tweets_pkey PRIMARY KEY (id);
ALTER TABLE public.bookmarks ADD CONSTRAINT bookmarks_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE;
ALTER TABLE public.likes ADD CONSTRAINT likes_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE;
ALTER TABLE public.retweets ADD CONSTRAINT retweets_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE;
ALTER TABLE public.tweets ADD CONSTRAINT tweets_reply_to_fkey FOREIGN KEY (reply_to) REFERENCES public.tweets(id) ON DELETE CASCADE;
ALTER TABLE public.tweets ADD CONSTRAINT tweets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweets TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweets TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweets TO service_role;
CREATE INDEX tweets_created_idx ON public.tweets (created_at DESC);
CREATE INDEX tweets_reply_idx ON public.tweets (reply_to);
CREATE INDEX tweets_user_idx ON public.tweets (user_id, created_at DESC);
CREATE TRIGGER on_reply AFTER INSERT ON public.tweets FOR EACH ROW EXECUTE FUNCTION public.notify_on_reply();
CREATE POLICY "tweets viewable by everyone" ON public.tweets FOR SELECT USING (true);
CREATE POLICY "users delete own tweets" ON public.tweets FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY "users insert own tweets" ON public.tweets FOR INSERT WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.profiles ADD COLUMN verified boolean DEFAULT false NOT NULL;
ALTER TABLE public.profiles ADD COLUMN is_protected boolean DEFAULT false NOT NULL;
ALTER TABLE public.profiles ADD COLUMN dm_allow_from text DEFAULT 'following' NOT NULL;
ALTER TABLE public.profiles ADD COLUMN allow_calls_from text DEFAULT 'following' NOT NULL;
ALTER TABLE public.profiles ADD COLUMN pinned_tweet_id uuid;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_dm_allow_from_check CHECK ((dm_allow_from = ANY (ARRAY['following'::text, 'verified'::text, 'anyone'::text, 'previous'::text])));
ALTER TABLE public.profiles ADD CONSTRAINT profiles_allow_calls_from_check CHECK ((allow_calls_from = ANY (ARRAY['following'::text, 'verified'::text, 'anyone'::text, 'previous'::text])));
ALTER TABLE public.profiles ADD CONSTRAINT profiles_pinned_tweet_id_fkey FOREIGN KEY (pinned_tweet_id) REFERENCES public.tweets(id) ON DELETE SET NULL;

CREATE TABLE public.follow_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  requester_id uuid NOT NULL,
  target_id uuid NOT NULL,
  status text DEFAULT 'pending' NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT follow_requests_pkey PRIMARY KEY (id),
  CONSTRAINT follow_requests_requester_id_target_id_key UNIQUE (requester_id, target_id),
  CONSTRAINT follow_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'rejected'::text]))),
  CONSTRAINT follow_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT follow_requests_target_id_fkey FOREIGN KEY (target_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.follow_requests ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.follow_requests TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.follow_requests TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.follow_requests TO service_role;
CREATE INDEX follow_requests_target_idx ON public.follow_requests (target_id, status, created_at DESC);
CREATE POLICY "create own follow request" ON public.follow_requests FOR INSERT WITH CHECK ((auth.uid() = requester_id));
CREATE POLICY "follow request visible to requester or target" ON public.follow_requests FOR SELECT USING (((auth.uid() = requester_id) OR (auth.uid() = target_id)));
CREATE POLICY "target updates follow request" ON public.follow_requests FOR UPDATE USING ((auth.uid() = target_id));

CREATE TABLE public.conversations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  kind text DEFAULT 'direct' NOT NULL,
  title text,
  image_url text,
  created_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT conversations_pkey PRIMARY KEY (id),
  CONSTRAINT conversations_kind_check CHECK ((kind = ANY (ARRAY['direct'::text, 'group'::text]))),
  CONSTRAINT conversations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.conversations TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.conversations TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.conversations TO service_role;
CREATE POLICY "create conversation as self" ON public.conversations FOR INSERT WITH CHECK ((auth.uid() = created_by));

CREATE TABLE public.dm_messages (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  conversation_id uuid NOT NULL,
  sender_id uuid NOT NULL,
  reply_to_message_id uuid,
  content text NOT NULL,
  kind text DEFAULT 'text' NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT dm_messages_pkey PRIMARY KEY (id),
  CONSTRAINT dm_messages_content_check CHECK ((char_length(content) <= 2000)),
  CONSTRAINT dm_messages_kind_check CHECK ((kind = ANY (ARRAY['text'::text, 'shared_post'::text, 'system'::text]))),
  CONSTRAINT dm_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE,
  CONSTRAINT dm_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT dm_messages_reply_to_message_id_fkey FOREIGN KEY (reply_to_message_id) REFERENCES public.dm_messages(id) ON DELETE SET NULL
);
ALTER TABLE public.dm_messages ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_messages TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_messages TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_messages TO service_role;
CREATE INDEX dm_msg_conv_created_idx ON public.dm_messages (conversation_id, created_at DESC);

CREATE TABLE public.conversation_members (
  conversation_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text DEFAULT 'member' NOT NULL,
  joined_at timestamp with time zone DEFAULT now() NOT NULL,
  muted_until timestamp with time zone,
  last_read_message_id uuid,
  deleted_at timestamp with time zone,
  CONSTRAINT conversation_members_pkey PRIMARY KEY (conversation_id, user_id),
  CONSTRAINT conversation_members_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'member'::text]))),
  CONSTRAINT conversation_members_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE,
  CONSTRAINT conversation_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT conversation_members_last_read_message_id_fkey FOREIGN KEY (last_read_message_id) REFERENCES public.dm_messages(id) ON DELETE SET NULL
);
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.conversation_members TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.conversation_members TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.conversation_members TO service_role;
CREATE INDEX conv_member_user_idx ON public.conversation_members (user_id, joined_at DESC);

CREATE TABLE public.dm_message_attachments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  message_id uuid NOT NULL,
  type text NOT NULL,
  url text NOT NULL,
  mime text,
  size_bytes bigint,
  meta jsonb DEFAULT '{}'::jsonb NOT NULL,
  CONSTRAINT dm_message_attachments_pkey PRIMARY KEY (id),
  CONSTRAINT dm_message_attachments_type_check CHECK ((type = ANY (ARRAY['image'::text, 'video'::text, 'gif'::text, 'file'::text, 'link'::text]))),
  CONSTRAINT dm_message_attachments_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.dm_messages(id) ON DELETE CASCADE
);
ALTER TABLE public.dm_message_attachments ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_attachments TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_attachments TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_attachments TO service_role;

CREATE TABLE public.dm_message_reactions (
  message_id uuid NOT NULL,
  user_id uuid NOT NULL,
  emoji text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT dm_message_reactions_pkey PRIMARY KEY (message_id, user_id, emoji),
  CONSTRAINT dm_message_reactions_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.dm_messages(id) ON DELETE CASCADE,
  CONSTRAINT dm_message_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.dm_message_reactions ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_reactions TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_reactions TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_reactions TO service_role;

CREATE TABLE public.dm_message_receipts (
  message_id uuid NOT NULL,
  user_id uuid NOT NULL,
  status text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT dm_message_receipts_pkey PRIMARY KEY (message_id, user_id),
  CONSTRAINT dm_message_receipts_status_check CHECK ((status = ANY (ARRAY['sent'::text, 'delivered'::text, 'read'::text, 'failed'::text]))),
  CONSTRAINT dm_message_receipts_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.dm_messages(id) ON DELETE CASCADE,
  CONSTRAINT dm_message_receipts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.dm_message_receipts ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_receipts TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_receipts TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_message_receipts TO service_role;
CREATE INDEX dm_receipt_user_idx ON public.dm_message_receipts (user_id, status, updated_at DESC);

CREATE TABLE public.dm_conversation_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  conversation_id uuid NOT NULL,
  recipient_id uuid NOT NULL,
  requester_id uuid NOT NULL,
  status text DEFAULT 'pending' NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  reviewed_at timestamp with time zone,
  CONSTRAINT dm_conversation_requests_pkey PRIMARY KEY (id),
  CONSTRAINT dm_conversation_requests_conversation_id_key UNIQUE (conversation_id),
  CONSTRAINT dm_conversation_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'deleted'::text, 'blocked'::text, 'reported'::text]))),
  CONSTRAINT dm_conversation_requests_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE,
  CONSTRAINT dm_conversation_requests_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT dm_conversation_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.dm_conversation_requests ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_conversation_requests TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_conversation_requests TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_conversation_requests TO service_role;
CREATE INDEX dm_request_recipient_idx ON public.dm_conversation_requests (recipient_id, status, created_at DESC);

CREATE TABLE public.dm_reports (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  reporter_id uuid NOT NULL,
  conversation_id uuid,
  message_id uuid,
  reason text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT dm_reports_pkey PRIMARY KEY (id),
  CONSTRAINT dm_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT dm_reports_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE,
  CONSTRAINT dm_reports_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.dm_messages(id) ON DELETE CASCADE
);
ALTER TABLE public.dm_reports ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_reports TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_reports TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_reports TO service_role;

CREATE TABLE public.dm_blocks (
  blocker_id uuid NOT NULL,
  blocked_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT dm_blocks_pkey PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT dm_blocks_check CHECK ((blocker_id <> blocked_id)),
  CONSTRAINT dm_blocks_blocker_id_fkey FOREIGN KEY (blocker_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT dm_blocks_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.dm_blocks ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_blocks TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_blocks TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.dm_blocks TO service_role;

CREATE POLICY "members see conversations" ON public.conversations FOR SELECT USING (EXISTS ( SELECT 1
   FROM public.conversation_members cm
  WHERE ((cm.conversation_id = conversations.id) AND (cm.user_id = auth.uid()) AND (cm.deleted_at IS NULL))));

CREATE POLICY "members see conversation members" ON public.conversation_members FOR SELECT USING (EXISTS ( SELECT 1
   FROM public.conversation_members cm
  WHERE ((cm.conversation_id = conversation_members.conversation_id) AND (cm.user_id = auth.uid()) AND (cm.deleted_at IS NULL))));
CREATE POLICY "members update own conversation state" ON public.conversation_members FOR UPDATE USING ((auth.uid() = user_id));

CREATE POLICY "members see dm messages" ON public.dm_messages FOR SELECT USING (EXISTS ( SELECT 1
   FROM public.conversation_members cm
  WHERE ((cm.conversation_id = dm_messages.conversation_id) AND (cm.user_id = auth.uid()) AND (cm.deleted_at IS NULL))));
CREATE POLICY "members send dm messages" ON public.dm_messages FOR INSERT WITH CHECK (((auth.uid() = sender_id) AND (EXISTS ( SELECT 1
   FROM public.conversation_members cm
  WHERE ((cm.conversation_id = dm_messages.conversation_id) AND (cm.user_id = auth.uid()) AND (cm.deleted_at IS NULL))))));

CREATE POLICY "members see dm attachments" ON public.dm_message_attachments FOR SELECT USING (EXISTS ( SELECT 1
   FROM (public.dm_messages m
     JOIN public.conversation_members cm ON ((cm.conversation_id = m.conversation_id)))
  WHERE ((m.id = dm_message_attachments.message_id) AND (cm.user_id = auth.uid()) AND (cm.deleted_at IS NULL))));
CREATE POLICY "sender inserts dm attachments" ON public.dm_message_attachments FOR INSERT WITH CHECK (EXISTS ( SELECT 1
   FROM public.dm_messages m
  WHERE ((m.id = dm_message_attachments.message_id) AND (m.sender_id = auth.uid()))));

CREATE POLICY "members see dm reactions" ON public.dm_message_reactions FOR SELECT USING (EXISTS ( SELECT 1
   FROM (public.dm_messages m
     JOIN public.conversation_members cm ON ((cm.conversation_id = m.conversation_id)))
  WHERE ((m.id = dm_message_reactions.message_id) AND (cm.user_id = auth.uid()) AND (cm.deleted_at IS NULL))));
CREATE POLICY "react as self" ON public.dm_message_reactions FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "remove own reaction" ON public.dm_message_reactions FOR DELETE USING ((auth.uid() = user_id));

CREATE POLICY "member sees own receipts" ON public.dm_message_receipts FOR SELECT USING ((auth.uid() = user_id));
CREATE POLICY "member inserts own receipts" ON public.dm_message_receipts FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "member updates own receipts" ON public.dm_message_receipts FOR UPDATE USING ((auth.uid() = user_id));

CREATE POLICY "recipient or requester sees requests" ON public.dm_conversation_requests FOR SELECT USING (((auth.uid() = recipient_id) OR (auth.uid() = requester_id)));
CREATE POLICY "requester creates request" ON public.dm_conversation_requests FOR INSERT WITH CHECK ((auth.uid() = requester_id));
CREATE POLICY "recipient resolves request" ON public.dm_conversation_requests FOR UPDATE USING ((auth.uid() = recipient_id));

CREATE POLICY "report as self" ON public.dm_reports FOR INSERT WITH CHECK ((auth.uid() = reporter_id));

CREATE POLICY "see own dm blocks" ON public.dm_blocks FOR SELECT USING ((auth.uid() = blocker_id));
CREATE POLICY "create own dm block" ON public.dm_blocks FOR INSERT WITH CHECK ((auth.uid() = blocker_id));
CREATE POLICY "remove own dm block" ON public.dm_blocks FOR DELETE USING ((auth.uid() = blocker_id));

ALTER PUBLICATION supabase_realtime ADD TABLE public.dm_messages, TABLE public.dm_conversation_requests;
