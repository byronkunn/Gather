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
