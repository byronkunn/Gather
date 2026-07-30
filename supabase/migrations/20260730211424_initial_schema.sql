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

ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['like'::text, 'retweet'::text, 'reply'::text, 'follow'::text, 'mention'::text, 'quote'::text, 'message'::text, 'message_request'::text, 'community'::text, 'announcement'::text])));

CREATE FUNCTION public.can_view_tweet(target_tweet_id uuid, viewer_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.tweets t
    where t.id = target_tweet_id
      and t.deleted_at is null
      and (t.status = 'published' or t.user_id = viewer_id)
  );
$function$;

CREATE FUNCTION public.can_reply_to_tweet(target_tweet_id uuid, replier_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

ALTER TABLE public.tweets ADD COLUMN status text DEFAULT 'published' NOT NULL;
ALTER TABLE public.tweets ADD COLUMN quote_tweet_id uuid;
ALTER TABLE public.tweets ADD COLUMN reply_audience text DEFAULT 'everyone' NOT NULL;
ALTER TABLE public.tweets ADD COLUMN sensitive boolean DEFAULT false NOT NULL;
ALTER TABLE public.tweets ADD COLUMN thread_root_id uuid;
ALTER TABLE public.tweets ADD COLUMN thread_position integer DEFAULT 0 NOT NULL;
ALTER TABLE public.tweets ADD COLUMN language_code text;
ALTER TABLE public.tweets ADD COLUMN edited_at timestamp with time zone;
ALTER TABLE public.tweets ADD COLUMN deleted_at timestamp with time zone;
ALTER TABLE public.tweets ADD CONSTRAINT tweets_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text])));
ALTER TABLE public.tweets ADD CONSTRAINT tweets_reply_audience_check CHECK ((reply_audience = ANY (ARRAY['everyone'::text, 'following'::text, 'mentioned'::text])));
ALTER TABLE public.tweets ADD CONSTRAINT tweets_thread_position_check CHECK ((thread_position >= 0));
ALTER TABLE public.tweets ADD CONSTRAINT tweets_quote_tweet_id_fkey FOREIGN KEY (quote_tweet_id) REFERENCES public.tweets(id) ON DELETE SET NULL;
ALTER TABLE public.tweets ADD CONSTRAINT tweets_thread_root_id_fkey FOREIGN KEY (thread_root_id) REFERENCES public.tweets(id) ON DELETE SET NULL;
CREATE INDEX tweets_status_created_idx ON public.tweets (status, created_at DESC);
CREATE INDEX tweets_thread_root_idx ON public.tweets (thread_root_id, thread_position);
CREATE INDEX tweets_quote_idx ON public.tweets (quote_tweet_id);
GRANT UPDATE ON public.tweets TO authenticated;

DROP POLICY "tweets viewable by everyone" ON public.tweets;
DROP POLICY "users insert own tweets" ON public.tweets;
CREATE POLICY "published tweets viewable by everyone" ON public.tweets FOR SELECT USING (((status = 'published'::text) AND (deleted_at IS NULL)));
CREATE POLICY "users view own tweets" ON public.tweets FOR SELECT USING ((auth.uid() = user_id));
CREATE POLICY "users insert own tweets" ON public.tweets FOR INSERT WITH CHECK (((auth.uid() = user_id) AND public.can_reply_to_tweet(reply_to, user_id)));
CREATE POLICY "users update own tweets" ON public.tweets FOR UPDATE USING ((auth.uid() = user_id));

CREATE TABLE public.tweet_media (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tweet_id uuid NOT NULL,
  type text NOT NULL,
  url text NOT NULL,
  alt_text text,
  sensitive boolean DEFAULT false NOT NULL,
  position smallint DEFAULT 0 NOT NULL,
  mime text,
  width integer,
  height integer,
  duration_ms integer,
  meta jsonb DEFAULT '{}'::jsonb NOT NULL,
  CONSTRAINT tweet_media_pkey PRIMARY KEY (id),
  CONSTRAINT tweet_media_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE,
  CONSTRAINT tweet_media_type_check CHECK ((type = ANY (ARRAY['image'::text, 'video'::text, 'gif'::text, 'link'::text]))),
  CONSTRAINT tweet_media_position_check CHECK ((position >= 0))
);
ALTER TABLE public.tweet_media ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_media TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_media TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_media TO service_role;
CREATE INDEX tweet_media_tweet_idx ON public.tweet_media (tweet_id, position);

CREATE TABLE public.tweet_media_tags (
  media_id uuid NOT NULL,
  tagged_user_id uuid NOT NULL,
  x numeric(5,2),
  y numeric(5,2),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT tweet_media_tags_pkey PRIMARY KEY (media_id, tagged_user_id),
  CONSTRAINT tweet_media_tags_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.tweet_media(id) ON DELETE CASCADE,
  CONSTRAINT tweet_media_tags_tagged_user_id_fkey FOREIGN KEY (tagged_user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.tweet_media_tags ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_media_tags TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_media_tags TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_media_tags TO service_role;

CREATE TABLE public.tweet_hashtags (
  tweet_id uuid NOT NULL,
  tag text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT tweet_hashtags_pkey PRIMARY KEY (tweet_id, tag),
  CONSTRAINT tweet_hashtags_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE
);
ALTER TABLE public.tweet_hashtags ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_hashtags TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_hashtags TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_hashtags TO service_role;
CREATE INDEX tweet_hashtags_tag_idx ON public.tweet_hashtags (tag);

CREATE TABLE public.tweet_mentions (
  tweet_id uuid NOT NULL,
  mentioned_user_id uuid NOT NULL,
  mentioned_by_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  removed_at timestamp with time zone,
  CONSTRAINT tweet_mentions_pkey PRIMARY KEY (tweet_id, mentioned_user_id),
  CONSTRAINT tweet_mentions_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE,
  CONSTRAINT tweet_mentions_mentioned_user_id_fkey FOREIGN KEY (mentioned_user_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT tweet_mentions_mentioned_by_id_fkey FOREIGN KEY (mentioned_by_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.tweet_mentions ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_mentions TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_mentions TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_mentions TO service_role;
CREATE INDEX tweet_mentions_user_idx ON public.tweet_mentions (mentioned_user_id, created_at DESC);

CREATE TABLE public.tweet_polls (
  tweet_id uuid NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  multiple_choice boolean DEFAULT false NOT NULL,
  ended_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT tweet_polls_pkey PRIMARY KEY (tweet_id),
  CONSTRAINT tweet_polls_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE
);
ALTER TABLE public.tweet_polls ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_polls TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_polls TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_polls TO service_role;

CREATE TABLE public.tweet_poll_options (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tweet_id uuid NOT NULL,
  label text NOT NULL,
  position smallint NOT NULL,
  CONSTRAINT tweet_poll_options_pkey PRIMARY KEY (id),
  CONSTRAINT tweet_poll_options_tweet_id_position_key UNIQUE (tweet_id, position),
  CONSTRAINT tweet_poll_options_label_check CHECK ((char_length(label) <= 25)),
  CONSTRAINT tweet_poll_options_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweet_polls(tweet_id) ON DELETE CASCADE
);
ALTER TABLE public.tweet_poll_options ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_poll_options TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_poll_options TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_poll_options TO service_role;

CREATE TABLE public.tweet_poll_votes (
  tweet_id uuid NOT NULL,
  option_id uuid NOT NULL,
  user_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT tweet_poll_votes_pkey PRIMARY KEY (option_id, user_id),
  CONSTRAINT tweet_poll_votes_tweet_id_user_id_key UNIQUE (tweet_id, user_id),
  CONSTRAINT tweet_poll_votes_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweet_polls(tweet_id) ON DELETE CASCADE,
  CONSTRAINT tweet_poll_votes_option_id_fkey FOREIGN KEY (option_id) REFERENCES public.tweet_poll_options(id) ON DELETE CASCADE,
  CONSTRAINT tweet_poll_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.tweet_poll_votes ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_poll_votes TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_poll_votes TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_poll_votes TO service_role;

CREATE TABLE public.tweet_conversation_mutes (
  tweet_id uuid NOT NULL,
  user_id uuid NOT NULL,
  muted_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT tweet_conversation_mutes_pkey PRIMARY KEY (tweet_id, user_id),
  CONSTRAINT tweet_conversation_mutes_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE,
  CONSTRAINT tweet_conversation_mutes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.tweet_conversation_mutes ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_conversation_mutes TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_conversation_mutes TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.tweet_conversation_mutes TO service_role;

CREATE TABLE public.hidden_replies (
  tweet_id uuid NOT NULL,
  hidden_reply_id uuid NOT NULL,
  hidden_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT hidden_replies_pkey PRIMARY KEY (tweet_id, hidden_reply_id),
  CONSTRAINT hidden_replies_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE,
  CONSTRAINT hidden_replies_hidden_reply_id_fkey FOREIGN KEY (hidden_reply_id) REFERENCES public.tweets(id) ON DELETE CASCADE,
  CONSTRAINT hidden_replies_hidden_by_fkey FOREIGN KEY (hidden_by) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.hidden_replies ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.hidden_replies TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.hidden_replies TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.hidden_replies TO service_role;

CREATE TABLE public.removed_mentions (
  tweet_id uuid NOT NULL,
  user_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT removed_mentions_pkey PRIMARY KEY (tweet_id, user_id),
  CONSTRAINT removed_mentions_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE,
  CONSTRAINT removed_mentions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.removed_mentions ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.removed_mentions TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.removed_mentions TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.removed_mentions TO service_role;

CREATE TABLE public.account_mutes (
  muter_id uuid NOT NULL,
  muted_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone,
  CONSTRAINT account_mutes_pkey PRIMARY KEY (muter_id, muted_id),
  CONSTRAINT account_mutes_check CHECK ((muter_id <> muted_id)),
  CONSTRAINT account_mutes_muter_id_fkey FOREIGN KEY (muter_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT account_mutes_muted_id_fkey FOREIGN KEY (muted_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.account_mutes ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.account_mutes TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.account_mutes TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.account_mutes TO service_role;

CREATE TABLE public.muted_keywords (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  phrase text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone,
  CONSTRAINT muted_keywords_pkey PRIMARY KEY (id),
  CONSTRAINT muted_keywords_phrase_check CHECK ((char_length(phrase) > 0)),
  CONSTRAINT muted_keywords_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.muted_keywords ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.muted_keywords TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.muted_keywords TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.muted_keywords TO service_role;

CREATE TABLE public.content_reports (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  reporter_id uuid NOT NULL,
  tweet_id uuid,
  profile_id uuid,
  message_id uuid,
  reason text NOT NULL,
  details text,
  status text DEFAULT 'open' NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT content_reports_pkey PRIMARY KEY (id),
  CONSTRAINT content_reports_status_check CHECK ((status = ANY (ARRAY['open'::text, 'reviewing'::text, 'resolved'::text, 'dismissed'::text]))),
  CONSTRAINT content_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT content_reports_tweet_id_fkey FOREIGN KEY (tweet_id) REFERENCES public.tweets(id) ON DELETE CASCADE,
  CONSTRAINT content_reports_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT content_reports_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.dm_messages(id) ON DELETE CASCADE
);
ALTER TABLE public.content_reports ENABLE ROW LEVEL SECURITY;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.content_reports TO anon;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.content_reports TO authenticated;
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON public.content_reports TO service_role;

GRANT SELECT ON public.tweet_media, public.tweet_media_tags, public.tweet_hashtags, public.tweet_mentions, public.tweet_polls, public.tweet_poll_options, public.tweet_poll_votes TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.tweet_media, public.tweet_media_tags, public.tweet_hashtags, public.tweet_mentions, public.tweet_polls, public.tweet_poll_options TO authenticated;
GRANT INSERT, DELETE ON public.tweet_poll_votes TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.tweet_conversation_mutes, public.hidden_replies, public.removed_mentions, public.account_mutes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.muted_keywords TO authenticated;
GRANT SELECT, INSERT ON public.content_reports TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_tweet(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_reply_to_tweet(uuid, uuid) TO authenticated;

CREATE POLICY "tweet media visible with tweet" ON public.tweet_media FOR SELECT USING (public.can_view_tweet(tweet_id, auth.uid()));
CREATE POLICY "tweet media owned by author" ON public.tweet_media FOR INSERT WITH CHECK (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_media.tweet_id) AND (t.user_id = auth.uid()))));
CREATE POLICY "tweet media author updates" ON public.tweet_media FOR UPDATE USING (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_media.tweet_id) AND (t.user_id = auth.uid()))));
CREATE POLICY "tweet media author deletes" ON public.tweet_media FOR DELETE USING (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_media.tweet_id) AND (t.user_id = auth.uid()))));

CREATE POLICY "tweet media tags visible with tweet" ON public.tweet_media_tags FOR SELECT USING (EXISTS ( SELECT 1
   FROM public.tweet_media tm
   JOIN public.tweets t ON (t.id = tm.tweet_id)
  WHERE ((tm.id = tweet_media_tags.media_id) AND public.can_view_tweet(t.id, auth.uid()))));
CREATE POLICY "tweet media tags owned by author" ON public.tweet_media_tags FOR INSERT WITH CHECK (EXISTS ( SELECT 1
   FROM public.tweet_media tm
   JOIN public.tweets t ON (t.id = tm.tweet_id)
  WHERE ((tm.id = tweet_media_tags.media_id) AND (t.user_id = auth.uid()))));
CREATE POLICY "tweet media tags author deletes" ON public.tweet_media_tags FOR DELETE USING (EXISTS ( SELECT 1
   FROM public.tweet_media tm
   JOIN public.tweets t ON (t.id = tm.tweet_id)
  WHERE ((tm.id = tweet_media_tags.media_id) AND (t.user_id = auth.uid()))));

CREATE POLICY "hashtags viewable" ON public.tweet_hashtags FOR SELECT USING (true);
CREATE POLICY "authors manage hashtags" ON public.tweet_hashtags FOR INSERT WITH CHECK (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_hashtags.tweet_id) AND (t.user_id = auth.uid()))));
CREATE POLICY "authors delete hashtags" ON public.tweet_hashtags FOR DELETE USING (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_hashtags.tweet_id) AND (t.user_id = auth.uid()))));

CREATE POLICY "mentions visible to participant or public viewers" ON public.tweet_mentions FOR SELECT USING (((auth.uid() = mentioned_user_id) OR public.can_view_tweet(tweet_id, auth.uid())));
CREATE POLICY "authors create mentions" ON public.tweet_mentions FOR INSERT WITH CHECK (((auth.uid() = mentioned_by_id) AND (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_mentions.tweet_id) AND (t.user_id = auth.uid()))))));
CREATE POLICY "authors update mentions" ON public.tweet_mentions FOR UPDATE USING (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_mentions.tweet_id) AND (t.user_id = auth.uid()))));

CREATE POLICY "polls visible with tweet" ON public.tweet_polls FOR SELECT USING (public.can_view_tweet(tweet_id, auth.uid()));
CREATE POLICY "authors manage polls" ON public.tweet_polls FOR INSERT WITH CHECK (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_polls.tweet_id) AND (t.user_id = auth.uid()))));
CREATE POLICY "authors update polls" ON public.tweet_polls FOR UPDATE USING (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_polls.tweet_id) AND (t.user_id = auth.uid()))));
CREATE POLICY "authors delete polls" ON public.tweet_polls FOR DELETE USING (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_polls.tweet_id) AND (t.user_id = auth.uid()))));

CREATE POLICY "poll options visible with tweet" ON public.tweet_poll_options FOR SELECT USING (public.can_view_tweet(tweet_id, auth.uid()));
CREATE POLICY "authors manage poll options" ON public.tweet_poll_options FOR INSERT WITH CHECK (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_poll_options.tweet_id) AND (t.user_id = auth.uid()))));
CREATE POLICY "authors update poll options" ON public.tweet_poll_options FOR UPDATE USING (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_poll_options.tweet_id) AND (t.user_id = auth.uid()))));
CREATE POLICY "authors delete poll options" ON public.tweet_poll_options FOR DELETE USING (EXISTS ( SELECT 1
   FROM public.tweets t
  WHERE ((t.id = tweet_poll_options.tweet_id) AND (t.user_id = auth.uid()))));

CREATE POLICY "poll votes visible with tweet" ON public.tweet_poll_votes FOR SELECT USING (public.can_view_tweet(tweet_id, auth.uid()));
CREATE POLICY "users vote as self" ON public.tweet_poll_votes FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "users retract own vote" ON public.tweet_poll_votes FOR DELETE USING ((auth.uid() = user_id));

CREATE POLICY "users manage own conversation mutes" ON public.tweet_conversation_mutes FOR ALL USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "authors manage hidden replies" ON public.hidden_replies FOR SELECT USING ((auth.uid() = hidden_by));
CREATE POLICY "authors create hidden replies" ON public.hidden_replies FOR INSERT WITH CHECK ((auth.uid() = hidden_by));
CREATE POLICY "authors remove hidden replies" ON public.hidden_replies FOR DELETE USING ((auth.uid() = hidden_by));
CREATE POLICY "users manage removed mentions" ON public.removed_mentions FOR ALL USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "users manage account mutes" ON public.account_mutes FOR ALL USING ((auth.uid() = muter_id)) WITH CHECK ((auth.uid() = muter_id));
CREATE POLICY "users manage muted keywords" ON public.muted_keywords FOR ALL USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
CREATE POLICY "users view own reports" ON public.content_reports FOR SELECT USING ((auth.uid() = reporter_id));
CREATE POLICY "users create own reports" ON public.content_reports FOR INSERT WITH CHECK ((auth.uid() = reporter_id));

ALTER PUBLICATION supabase_realtime ADD TABLE public.tweets, TABLE public.tweet_media, TABLE public.tweet_poll_votes;
