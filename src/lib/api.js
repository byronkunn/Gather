// Central data layer — handles Supabase queries with interactive mock fallback when unconfigured.
import { supabase, isConfigured } from "./supabase";

// Pre-populated mock data for offline / demo mode
const MOCK_PROFILES = {
  "demo-user-id": {
    id: "demo-user-id",
    username: "alex",
    display_name: "Alex Rivera",
    avatar_url:
      "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&auto=format&fit=crop&q=80",
    cover_url:
      "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=1200&auto=format&fit=crop&q=80",
    bio: "Building modern web apps & exploring AI. Pair programming on Gather! 🚀",
    location: "San Francisco, CA",
    website: "https://github.com/byronkunn",
    created_at: new Date(Date.now() - 30 * 86400000).toISOString(),
    follower_count: 342,
    following_count: 184,
    verified: false,
  },
  "user-sarah": {
    id: "user-sarah",
    username: "sarah_dev",
    display_name: "Sarah Chen",
    avatar_url:
      "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150&auto=format&fit=crop&q=80",
    cover_url:
      "https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=1200&auto=format&fit=crop&q=80",
    bio: "Frontend Engineer @ Gather | React, Vite, CSS magician 🎨✨",
    location: "Seattle, WA",
    website: "https://sarahchen.dev",
    created_at: new Date(Date.now() - 120 * 86400000).toISOString(),
    follower_count: 1250,
    following_count: 420,
    verified: true,
  },
  "user-sam": {
    id: "user-sam",
    username: "sam_tech",
    display_name: "Sam Altman Jr.",
    avatar_url:
      "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&auto=format&fit=crop&q=80",
    bio: "AI researcher & open-source enthusiast.",
    created_at: new Date(Date.now() - 90 * 86400000).toISOString(),
    follower_count: 8900,
    following_count: 310,
    verified: true,
  },
};

let MOCK_TWEETS = [
  {
    id: "tweet-1",
    user_id: "user-sarah",
    content:
      "Just launched our new React + Vite web application! Check out the smooth theme toggling and real-time feel. What do you think? #react #webdev",
    image_url:
      "https://images.unsplash.com/photo-1555066931-4365d14bab8c?w=800&auto=format&fit=crop&q=80",
    reply_to: null,
    created_at: new Date(Date.now() - 3600000 * 2).toISOString(),
    author: MOCK_PROFILES["user-sarah"],
    like_count: 42,
    retweet_count: 12,
    reply_count: 3,
    liked: true,
    retweeted: false,
    bookmarked: false,
  },
  {
    id: "tweet-2",
    user_id: "user-sam",
    content:
      "The future of software development is pair programming with AI agents that understand full repositories and user intent. 🤖⚡",
    image_url: null,
    reply_to: null,
    created_at: new Date(Date.now() - 3600000 * 5).toISOString(),
    author: MOCK_PROFILES["user-sam"],
    like_count: 128,
    retweet_count: 34,
    reply_count: 15,
    liked: false,
    retweeted: true,
    bookmarked: true,
  },
  {
    id: "tweet-3",
    user_id: "demo-user-id",
    content:
      "Welcome to Gather! Try posting a tweet, switching between Light, Dim, and Lights Out themes, or searching for #react!",
    image_url: null,
    reply_to: null,
    created_at: new Date(Date.now() - 3600000 * 8).toISOString(),
    author: MOCK_PROFILES["demo-user-id"],
    like_count: 15,
    retweet_count: 4,
    reply_count: 1,
    liked: false,
    retweeted: false,
    bookmarked: false,
  },
];

let MOCK_FOLLOWS = new Set(["user-sarah"]);
let MOCK_TAG_FOLLOWS = new Set(["react"]);
let MOCK_MUTED_ACCOUNT_IDS = new Set();
let MOCK_MUTED_WORDS = [];
let MOCK_NOTIFICATIONS = [
  {
    id: "notif-1",
    user_id: "demo-user-id",
    type: "like",
    read: false,
    created_at: new Date(Date.now() - 1800000).toISOString(),
    actor: MOCK_PROFILES["user-sarah"],
    tweet: {
      id: "tweet-3",
      content: "Welcome to Gather! Try posting a tweet...",
    },
  },
  {
    id: "notif-2",
    user_id: "demo-user-id",
    type: "retweet",
    read: false,
    created_at: new Date(Date.now() - 3600000).toISOString(),
    actor: MOCK_PROFILES["user-sam"],
    tweet: {
      id: "tweet-3",
      content: "Welcome to Gather! Try posting a tweet...",
    },
  },
];

let MOCK_MESSAGES = [
  {
    id: "msg-1",
    sender_id: "user-sarah",
    recipient_id: "demo-user-id",
    content: "Hey Alex! How is the new Gather features coming along?",
    created_at: new Date(Date.now() - 7200000).toISOString(),
    read: false,
    sender: MOCK_PROFILES["user-sarah"],
    recipient: MOCK_PROFILES["demo-user-id"],
  },
  {
    id: "msg-2",
    sender_id: "demo-user-id",
    recipient_id: "user-sarah",
    content: "Hi Sarah! Everything is running smoothly and looks great!",
    created_at: new Date(Date.now() - 3600000).toISOString(),
    read: true,
    sender: MOCK_PROFILES["demo-user-id"],
    recipient: MOCK_PROFILES["user-sarah"],
  },
];

const MAX_HASHTAGS_PER_POST = 10;
const MAX_HASHTAG_LENGTH = 32;
const DEFAULT_NOTIFICATION_SETTINGS = {
  likes: true,
  reposts: true,
  follows: true,
  replies: true,
  mentions: true,
  verifiedOnly: false,
};

function getPreferenceKey(userId, key) {
  return `gather:${key}:${userId}`;
}

function readStoredJson(key, fallback) {
  if (typeof window === "undefined") return fallback;
  try {
    const value = window.localStorage.getItem(key);
    return value ? JSON.parse(value) : fallback;
  } catch {
    return fallback;
  }
}

function writeStoredJson(key, value) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // ignore storage failures
  }
}

const TWEET_FIELDS = `
  id, user_id, content, image_url, reply_to, created_at,
  status, quote_tweet_id, reply_audience, sensitive, thread_root_id, thread_position, language_code, edited_at, deleted_at,
  author:profiles!tweets_user_id_fkey (id, username, display_name, avatar_url, verified),
  media:tweet_media (id, type, url, alt_text, sensitive, position, mime, width, height, duration_ms, meta, tags:tweet_media_tags (tagged_user_id, x, y)),
  hashtags:tweet_hashtags (tag),
  mentions:tweet_mentions (mentioned_user_id, removed_at),
  poll:tweet_polls (expires_at, multiple_choice, ended_at, options:tweet_poll_options (id, label, position, votes:tweet_poll_votes (user_id))),
  like_count:likes(count),
  retweet_count:retweets(count),
  reply_count:tweets!reply_to(count)
`;

function shapeTweet(row) {
  if (!row) return null;
  const media = [...(row.media || [])].sort((a, b) => a.position - b.position);
  const primaryMedia =
    media.find((item) => item.type === "image") || media[0] || null;
  const poll = row.poll
    ? {
        ...row.poll,
        options: [...(row.poll.options || [])]
          .sort((a, b) => a.position - b.position)
          .map((option) => ({
            ...option,
            vote_count: option.votes?.length ?? 0,
          })),
      }
    : null;
  return {
    ...row,
    image_url: row.image_url || primaryMedia?.url || null,
    media,
    hashtags: (row.hashtags || []).map((item) => item.tag),
    mentions: (row.mentions || [])
      .filter((item) => !item.removed_at)
      .map((item) => item.mentioned_user_id),
    poll,
    like_count: row.like_count?.[0]?.count ?? 0,
    retweet_count: row.retweet_count?.[0]?.count ?? 0,
    reply_count: row.reply_count?.[0]?.count ?? 0,
    liked: false,
    retweeted: false,
    bookmarked: false,
  };
}

async function attachUserState(tweets, userId) {
  if (!userId || tweets.length === 0) return tweets;
  if (!isConfigured) {
    return tweets.map((t) => ({
      ...t,
      liked: Boolean(t.liked),
      retweeted: Boolean(t.retweeted),
      bookmarked: Boolean(t.bookmarked),
    }));
  }
  try {
    const ids = [...new Set(tweets.map((t) => t.id))];
    const [likes, retweets, bookmarks] = await Promise.all([
      supabase
        .from("likes")
        .select("tweet_id")
        .eq("user_id", userId)
        .in("tweet_id", ids),
      supabase
        .from("retweets")
        .select("tweet_id")
        .eq("user_id", userId)
        .in("tweet_id", ids),
      supabase
        .from("bookmarks")
        .select("tweet_id")
        .eq("user_id", userId)
        .in("tweet_id", ids),
    ]);
    const likedSet = new Set((likes.data || []).map((r) => r.tweet_id));
    const rtSet = new Set((retweets.data || []).map((r) => r.tweet_id));
    const bmSet = new Set((bookmarks.data || []).map((r) => r.tweet_id));
    return tweets.map((t) => ({
      ...t,
      liked: likedSet.has(t.id),
      retweeted: rtSet.has(t.id),
      bookmarked: bmSet.has(t.id),
    }));
  } catch {
    return tweets;
  }
}

function normalizeTweetOptions(options = {}) {
  return {
    status: options.status === "draft" ? "draft" : "published",
    quoteTweetId: options.quoteTweetId ?? null,
    replyAudience: options.replyAudience || "everyone",
    sensitive: Boolean(options.sensitive),
    threadRootId: options.threadRootId ?? null,
    threadPosition: Number.isInteger(options.threadPosition)
      ? options.threadPosition
      : 0,
    languageCode: options.languageCode || null,
    mediaAttachments: options.mediaAttachments || [],
    hashtags:
      options.hashtags?.map((tag) =>
        String(tag).replace(/^#/, "").toLowerCase(),
      ) || [],
    mentions:
      options.mentions?.map((username) => String(username).replace(/^@/, "")) ||
      [],
    poll: options.poll || null,
  };
}

function stripUrls(text) {
  return text.replace(/https?:\/\/\S+/gi, " ");
}

function extractHashtags(content) {
  const withoutUrls = stripUrls(content);
  const matches = [
    ...withoutUrls.matchAll(
      /(^|[^\w/])#([A-Za-z0-9_]{1,40})(?=$|[^A-Za-z0-9_])/g,
    ),
  ];
  return [
    ...new Set(
      matches.map((match) =>
        match[2].toLowerCase().slice(0, MAX_HASHTAG_LENGTH),
      ),
    ),
  ]
    .filter(Boolean)
    .slice(0, MAX_HASHTAGS_PER_POST);
}

function extractMentions(content) {
  return [
    ...new Set([...content.matchAll(/@(\w{1,30})/g)].map((match) => match[1])),
  ];
}

async function uploadMediaAsset(userId, attachment) {
  if (attachment.url) {
    return { ...attachment, url: attachment.url };
  }
  if (!attachment.file) {
    throw new Error("Media attachment is missing a file or URL");
  }
  const file = attachment.file;
  const ext = file.name.split(".").pop();
  const path = `${userId}/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;
  const { error } = await supabase.storage.from("media").upload(path, file);
  if (error) throw error;
  return {
    ...attachment,
    url: supabase.storage.from("media").getPublicUrl(path).data.publicUrl,
    mime: attachment.mime || file.type || null,
  };
}

async function resolveMentionedProfiles(usernames) {
  const unique = [...new Set(usernames.filter(Boolean))];
  if (unique.length === 0) return [];
  if (!isConfigured) {
    return Object.values(MOCK_PROFILES)
      .filter((profile) => unique.includes(profile.username))
      .map((profile) => ({ id: profile.id, username: profile.username }));
  }
  const { data, error } = await supabase
    .from("profiles")
    .select("id, username")
    .in("username", unique);
  if (error) throw error;
  return data || [];
}

async function createTweetRelations(
  tweetId,
  userId,
  content,
  options,
  legacyImageUrl,
) {
  const hashtags = [
    ...new Set([...options.hashtags, ...extractHashtags(content)]),
  ];
  const mentionUsernames = [
    ...new Set([...options.mentions, ...extractMentions(content)]),
  ];

  let uploadedMedia = options.mediaAttachments;
  if (legacyImageUrl) {
    uploadedMedia = [
      {
        type: "image",
        url: legacyImageUrl,
        altText: null,
        sensitive: options.sensitive,
        position: 0,
        tags: [],
      },
      ...uploadedMedia,
    ];
  }

  const mentions = await resolveMentionedProfiles(mentionUsernames);

  if (!isConfigured) {
    const tweet = MOCK_TWEETS.find((item) => item.id === tweetId);
    if (tweet) {
      tweet.status = options.status;
      tweet.quote_tweet_id = options.quoteTweetId;
      tweet.reply_audience = options.replyAudience;
      tweet.sensitive = options.sensitive;
      tweet.thread_root_id = options.threadRootId;
      tweet.thread_position = options.threadPosition;
      tweet.language_code = options.languageCode;
      tweet.media = uploadedMedia.map((item, index) => ({
        id: `${tweetId}-media-${index}`,
        type: item.type || "image",
        url: item.url,
        alt_text: item.altText || null,
        sensitive: Boolean(item.sensitive),
        position: index,
        tags: item.tags || [],
      }));
      tweet.hashtags = hashtags;
      tweet.tag_entities = hashtags.map((tag) => ({
        id: `tag-${tag}`,
        name: tag,
        normalized_name: tag,
        post_count:
          MOCK_TWEETS.filter((item) => (item.hashtags || []).includes(tag))
            .length + 1,
      }));
      tweet.mentions = mentions.map((item) => item.id);
      if (options.poll) {
        tweet.poll = {
          expires_at: options.poll.expiresAt,
          multiple_choice: Boolean(options.poll.multipleChoice),
          ended_at: null,
          options: (options.poll.options || []).map((label, index) => ({
            id: `${tweetId}-poll-${index}`,
            label,
            position: index,
            votes: [],
            vote_count: 0,
          })),
        };
      }
    }
    return;
  }

  if (uploadedMedia.length) {
    const mediaRows = uploadedMedia.map((item, index) => ({
      tweet_id: tweetId,
      type: item.type || "image",
      url: item.url,
      alt_text: item.altText || null,
      sensitive: item.sensitive ?? options.sensitive,
      position: item.position ?? index,
      mime: item.mime || null,
      width: item.width || null,
      height: item.height || null,
      duration_ms: item.durationMs || null,
      meta: item.meta || {},
    }));
    const { data: createdMedia, error: mediaError } = await supabase
      .from("tweet_media")
      .insert(mediaRows)
      .select("id, position");
    if (mediaError) throw mediaError;

    const mediaTags = (createdMedia || []).flatMap((mediaItem, index) =>
      (uploadedMedia[index]?.tags || []).map((tag) => ({
        media_id: mediaItem.id,
        tagged_user_id: tag.userId,
        x: tag.x ?? null,
        y: tag.y ?? null,
      })),
    );
    if (mediaTags.length) {
      const { error: mediaTagsError } = await supabase
        .from("tweet_media_tags")
        .insert(mediaTags);
      if (mediaTagsError) throw mediaTagsError;
    }
  }

  if (hashtags.length) {
    const { data: createdTags, error: tagError } = await supabase
      .from("tags")
      .upsert(
        hashtags.map((tag) => ({
          name: tag,
          normalized_name: tag,
        })),
        { onConflict: "normalized_name", ignoreDuplicates: false },
      )
      .select("id, normalized_name");
    if (tagError) throw tagError;

    const { error: postTagsError } = await supabase.from("post_tags").insert(
      (createdTags || []).map((tag) => ({
        post_id: tweetId,
        tag_id: tag.id,
      })),
    );
    if (postTagsError) throw postTagsError;

    const { error: hashtagError } = await supabase
      .from("tweet_hashtags")
      .insert(hashtags.map((tag) => ({ tweet_id: tweetId, tag })));
    if (hashtagError) throw hashtagError;
  }

  if (mentions.length) {
    const { error: mentionError } = await supabase
      .from("tweet_mentions")
      .insert(
        mentions.map((profile) => ({
          tweet_id: tweetId,
          mentioned_user_id: profile.id,
          mentioned_by_id: userId,
        })),
      );
    if (mentionError) throw mentionError;
  }

  if (options.poll?.options?.length) {
    const { error: pollError } = await supabase.from("tweet_polls").insert({
      tweet_id: tweetId,
      expires_at: options.poll.expiresAt,
      multiple_choice: Boolean(options.poll.multipleChoice),
    });
    if (pollError) throw pollError;

    const { error: optionsError } = await supabase
      .from("tweet_poll_options")
      .insert(
        options.poll.options.map((label, index) => ({
          tweet_id: tweetId,
          label,
          position: index,
        })),
      );
    if (optionsError) throw optionsError;
  }
}

function withTagEntities(tweet) {
  if (!tweet) return tweet;
  return {
    ...tweet,
    tag_entities:
      tweet.tag_entities ||
      (tweet.hashtags || []).map((tag) => ({
        id: `tag-${tag}`,
        name: tag,
        normalized_name: tag,
        post_count: 0,
      })),
  };
}

function getMockTagRecords() {
  const counts = new Map();
  for (const tweet of MOCK_TWEETS) {
    for (const tag of tweet.hashtags || extractHashtags(tweet.content || "")) {
      counts.set(tag, (counts.get(tag) || 0) + 1);
    }
  }
  return [...counts.entries()].map(([tag, post_count]) => ({
    id: `tag-${tag}`,
    name: tag,
    normalized_name: tag,
    description: "",
    post_count,
    created_at: new Date().toISOString(),
  }));
}

function dedupeFeedItems(items) {
  const seen = new Set();
  return items.filter((item) => {
    const key = item.tweet.id;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function tweetContainsMutedWord(tweet, mutedWords) {
  const haystack = `${tweet.content || ""} ${(tweet.hashtags || []).join(" ")}`.toLowerCase();
  return mutedWords.some((word) => haystack.includes(String(word).toLowerCase()));
}

function filterTweetsBySafety(tweets, filters) {
  return tweets.filter((tweet) => {
    if (!tweet) return false;
    if (filters.mutedAccountIds.has(tweet.user_id || tweet.author?.id)) return false;
    if (tweetContainsMutedWord(tweet, filters.mutedWords)) return false;
    return true;
  });
}

function filterFeedItemsBySafety(items, filters) {
  return items.filter((item) => {
    const tweet = item.tweet ?? item;
    if (filters.mutedAccountIds.has(tweet.user_id || tweet.author?.id)) return false;
    if (tweetContainsMutedWord(tweet, filters.mutedWords)) return false;
    return true;
  });
}

async function fetchSafetyFilters(userId) {
  if (!userId) {
    return { mutedAccountIds: new Set(), mutedWords: [] };
  }
  if (!isConfigured) {
    return {
      mutedAccountIds: new Set([...MOCK_MUTED_ACCOUNT_IDS]),
      mutedWords: [...MOCK_MUTED_WORDS],
    };
  }
  const [{ data: mutedAccounts }, { data: mutedWords }] = await Promise.all([
    supabase
      .from("account_mutes")
      .select("muted_id")
      .eq("muter_id", userId),
    supabase
      .from("muted_keywords")
      .select("phrase")
      .eq("user_id", userId),
  ]);
  return {
    mutedAccountIds: new Set((mutedAccounts || []).map((row) => row.muted_id)),
    mutedWords: (mutedWords || []).map((row) => row.phrase).filter(Boolean),
  };
}

function interleaveTagFeed(primaryItems, tagItems, every = 4) {
  if (tagItems.length === 0) return primaryItems;
  const output = [];
  let tagIndex = 0;

  for (let index = 0; index < primaryItems.length; index += 1) {
    output.push(primaryItems[index]);
    if ((index + 1) % every === 0 && tagIndex < tagItems.length) {
      output.push(tagItems[tagIndex]);
      tagIndex += 1;
    }
  }

  while (
    tagIndex < tagItems.length &&
    output.length <
      primaryItems.length +
        Math.min(tagItems.length, Math.ceil(primaryItems.length / every))
  ) {
    output.push(tagItems[tagIndex]);
    tagIndex += 1;
  }

  return output;
}

async function fetchFollowedTagNames(userId) {
  if (!isConfigured) return [...MOCK_TAG_FOLLOWS];
  const { data, error } = await supabase
    .from("user_tag_follows")
    .select("tags:tags!user_tag_follows_tag_id_fkey (normalized_name)")
    .eq("user_id", userId)
    .eq("show_in_home", true);
  if (error) throw error;
  return (data || []).map((row) => row.tags?.normalized_name).filter(Boolean);
}

async function fetchTagRowsByNames(tagNames) {
  const unique = [
    ...new Set(
      tagNames
        .filter(Boolean)
        .map((tag) => String(tag).replace(/^#/, "").toLowerCase()),
    ),
  ];
  if (unique.length === 0) return [];
  const { data, error } = await supabase
    .from("tags")
    .select("id, name, normalized_name, post_count")
    .in("normalized_name", unique);
  if (error) throw error;
  return data || [];
}

async function fetchTagPostsByNames(tagNames, userId, limit = 40) {
  if (tagNames.length === 0) return [];
  if (!isConfigured) {
    return dedupeFeedItems(
      MOCK_TWEETS.filter((tweet) =>
        (tweet.hashtags || []).some((tag) => tagNames.includes(tag)),
      )
        .filter((tweet) => tweet.status !== "draft" && !tweet.deleted_at)
        .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
        .slice(0, limit)
        .map((tweet) => {
          const reasonTag = (tweet.hashtags || []).find((tag) =>
            tagNames.includes(tag),
          );
          return {
            sortAt: tweet.created_at,
            tweet: withTagEntities(tweet),
            reasonTag,
          };
        }),
    );
  }

  const tagRows = await fetchTagRowsByNames(tagNames);
  if (tagRows.length === 0) return [];

  const { data, error } = await supabase
    .from("post_tags")
    .select(`created_at, tag_id, tweet:tweets (${TWEET_FIELDS})`)
    .in(
      "tag_id",
      tagRows.map((tag) => tag.id),
    )
    .order("created_at", { ascending: false })
    .limit(limit * 3);
  if (error) throw error;

  const tagNameById = new Map(
    tagRows.map((tag) => [tag.id, tag.normalized_name]),
  );

  const shaped = (data || [])
    .filter((row) => row.tweet)
    .map((row) => ({
      sortAt: row.tweet.created_at,
      tweet: shapeTweet(row.tweet),
      reasonTag: tagNameById.get(row.tag_id) || null,
    }))
    .filter((item) => item.tweet.user_id !== userId);

  const deduped = dedupeFeedItems(shaped).slice(0, limit);
  const withState = await attachUserState(
    deduped.map((item) => item.tweet),
    userId,
  );
  return deduped.map((item, index) => ({
    ...item,
    tweet: withTagEntities(withState[index]),
  }));
}

// ---------- FEED ----------
export async function fetchFeed(userId, tab) {
  if (!isConfigured) {
    let list = [...MOCK_TWEETS].filter(
      (t) => !t.reply_to && t.status !== "draft" && !t.deleted_at,
    );
    if (tab === "following") {
      const followingItems = list.filter(
        (t) => MOCK_FOLLOWS.has(t.user_id) || t.user_id === userId,
      );
      const tagItems = await fetchTagPostsByNames([...MOCK_TAG_FOLLOWS], userId, 20);
      const mixed = interleaveTagFeed(
        followingItems.map((t) => ({
          sortAt: t.created_at,
          tweet: withTagEntities(t),
        })),
        tagItems.filter(
          (item) => !followingItems.some((tweet) => tweet.id === item.tweet.id),
        ),
      );
      return filterFeedItemsBySafety(mixed, await fetchSafetyFilters(userId));
    }
    const items = list.map((t) => ({
      sortAt: t.created_at,
      tweet: withTagEntities(t),
    }));
    return filterFeedItemsBySafety(items, await fetchSafetyFilters(userId));
  }

  let authorIds = null;
  if (tab === "following") {
    const { data, error } = await supabase
      .from("follows")
      .select("following_id")
      .eq("follower_id", userId);
    if (error) throw error;
    authorIds = [...(data || []).map((r) => r.following_id), userId];
  }

  let tweetQuery = supabase
    .from("tweets")
    .select(TWEET_FIELDS)
    .is("reply_to", null)
    .eq("status", "published")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(50);
  let rtQuery = supabase
    .from("retweets")
    .select(
      `created_at, retweeter:profiles!retweets_user_id_fkey (id, username, display_name), tweet:tweets (${TWEET_FIELDS})`,
    )
    .order("created_at", { ascending: false })
    .limit(20);
  if (authorIds) {
    tweetQuery = tweetQuery.in("user_id", authorIds);
    rtQuery = rtQuery.in("user_id", authorIds);
  }

  const [
    { data: tweets, error: tweetsError },
    { data: rts, error: retweetsError },
  ] = await Promise.all([tweetQuery, rtQuery]);
  if (tweetsError) throw tweetsError;
  if (retweetsError) throw retweetsError;

  const items = [
    ...(tweets || []).map((t) => ({
      sortAt: t.created_at,
      tweet: withTagEntities(shapeTweet(t)),
    })),
    ...(rts || [])
      .filter((r) => r.tweet)
      .map((r) => ({
        sortAt: r.created_at,
        retweetedBy: r.retweeter,
        tweet: withTagEntities(shapeTweet(r.tweet)),
      })),
  ].sort((a, b) => new Date(b.sortAt) - new Date(a.sortAt));

  let deduped = dedupeFeedItems(items);

  if (tab === "following") {
    const tagNames = await fetchFollowedTagNames(userId);
    const tagItems = await fetchTagPostsByNames(tagNames, userId, 20);
    const nonDuplicateTagItems = tagItems.filter(
      (item) =>
        !deduped.some((existing) => existing.tweet.id === item.tweet.id),
    );
    deduped = interleaveTagFeed(deduped, nonDuplicateTagItems);
  }

  deduped = filterFeedItemsBySafety(deduped, await fetchSafetyFilters(userId));

  const withState = await attachUserState(
    deduped.map((i) => i.tweet),
    userId,
  );
  return deduped.map((item, i) => ({ ...item, tweet: withState[i] }));
}

// ---------- SINGLE TWEET / THREAD ----------
export async function fetchTweet(id, userId) {
  if (!isConfigured) {
    const t = MOCK_TWEETS.find((x) => x.id === id);
    if (!t) throw new Error("Tweet not found");
    return t;
  }
  const { data, error } = await supabase
    .from("tweets")
    .select(TWEET_FIELDS)
    .eq("id", id)
    .is("deleted_at", null)
    .single();
  if (error) throw error;
  const visibleTweets = filterTweetsBySafety([shapeTweet(data)], await fetchSafetyFilters(userId));
  if (visibleTweets.length === 0) throw new Error("Tweet unavailable");
  const [t] = await attachUserState(visibleTweets, userId);
  return t;
}

export async function fetchReplies(tweetId, userId) {
  if (!isConfigured) {
    const replies = MOCK_TWEETS.filter((x) => x.reply_to === tweetId);
    return replies;
  }
  const { data, error } = await supabase
    .from("tweets")
    .select(TWEET_FIELDS)
    .eq("reply_to", tweetId)
    .eq("status", "published")
    .is("deleted_at", null)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return attachUserState(filterTweetsBySafety((data || []).map(shapeTweet), await fetchSafetyFilters(userId)), userId);
}

// ---------- COMPOSE ----------
export async function createTweet(
  userId,
  content,
  imageFile,
  replyTo = null,
  options = {},
) {
  const normalized = normalizeTweetOptions(options);
  if (!isConfigured) {
    const author = MOCK_PROFILES[userId] || MOCK_PROFILES["demo-user-id"];
    let image_url = null;
    if (imageFile) {
      image_url = URL.createObjectURL(imageFile);
    }
    const newTweet = {
      id: "tweet-" + Date.now(),
      user_id: author.id,
      content,
      image_url,
      reply_to: replyTo,
      status: normalized.status,
      quote_tweet_id: normalized.quoteTweetId,
      reply_audience: normalized.replyAudience,
      sensitive: normalized.sensitive,
      thread_root_id: normalized.threadRootId,
      thread_position: normalized.threadPosition,
      language_code: normalized.languageCode,
      created_at: new Date().toISOString(),
      author,
      like_count: 0,
      retweet_count: 0,
      reply_count: 0,
      liked: false,
      retweeted: false,
      bookmarked: false,
    };
    MOCK_TWEETS.unshift(newTweet);
    await createTweetRelations(
      newTweet.id,
      userId,
      content,
      normalized,
      image_url,
    );
    if (replyTo) {
      const parent = MOCK_TWEETS.find((t) => t.id === replyTo);
      if (parent) parent.reply_count++;
    }
    return shapeTweet(newTweet);
  }

  let image_url = null;
  let uploadedAttachments = normalized.mediaAttachments;
  if (imageFile) {
    image_url = await uploadImage(userId, imageFile);
  }
  if (uploadedAttachments.length) {
    uploadedAttachments = await Promise.all(
      uploadedAttachments.map((attachment) =>
        uploadMediaAsset(userId, attachment),
      ),
    );
  }
  const { data, error } = await supabase
    .from("tweets")
    .insert({
      user_id: userId,
      content,
      image_url,
      reply_to: replyTo,
      status: normalized.status,
      quote_tweet_id: normalized.quoteTweetId,
      reply_audience: normalized.replyAudience,
      sensitive: normalized.sensitive,
      thread_root_id: normalized.threadRootId,
      thread_position: normalized.threadPosition,
      language_code: normalized.languageCode,
    })
    .select(TWEET_FIELDS)
    .single();
  if (error) throw error;
  await createTweetRelations(
    data.id,
    userId,
    content,
    { ...normalized, mediaAttachments: uploadedAttachments },
    image_url,
  );
  return fetchTweet(data.id, userId);
}

export async function createThread(userId, posts, options = {}) {
  if (!posts?.length) return [];
  const created = [];
  let rootId = null;
  let previousId = null;

  for (const [index, post] of posts.entries()) {
    const tweet = await createTweet(
      userId,
      post.content,
      post.imageFile ?? null,
      previousId,
      {
        ...options,
        ...post,
        threadRootId: rootId,
        threadPosition: index,
      },
    );
    if (!rootId) rootId = tweet.id;
    previousId = tweet.id;
    created.push(tweet);
  }

  return created;
}

export async function fetchTweetThread(rootId, userId) {
  if (!isConfigured) {
    return MOCK_TWEETS.filter(
      (tweet) => tweet.id === rootId || tweet.thread_root_id === rootId,
    ).sort((a, b) => (a.thread_position ?? 0) - (b.thread_position ?? 0));
  }
  const { data, error } = await supabase
    .from("tweets")
    .select(TWEET_FIELDS)
    .or(`id.eq.${rootId},thread_root_id.eq.${rootId}`)
    .eq("status", "published")
    .is("deleted_at", null)
    .order("thread_position", { ascending: true });
  if (error) throw error;
  return attachUserState((data || []).map(shapeTweet), userId);
}

export async function fetchDrafts(userId) {
  if (!isConfigured) {
    return MOCK_TWEETS.filter(
      (tweet) => tweet.user_id === userId && tweet.status === "draft",
    );
  }
  const { data, error } = await supabase
    .from("tweets")
    .select(TWEET_FIELDS)
    .eq("user_id", userId)
    .eq("status", "draft")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data || []).map(shapeTweet);
}

export async function pinTweetOnProfile(userId, tweetId) {
  return updateProfile(userId, { pinned_tweet_id: tweetId });
}

export async function clearPinnedTweet(userId) {
  return updateProfile(userId, { pinned_tweet_id: null });
}

export function saveDraft(userId, content, imageFile = null, options = {}) {
  return createTweet(userId, content, imageFile, options.replyTo ?? null, {
    ...options,
    status: "draft",
  });
}

export async function deleteTweet(id) {
  if (!isConfigured) {
    MOCK_TWEETS = MOCK_TWEETS.filter((t) => t.id !== id);
    return;
  }
  const { error } = await supabase.from("tweets").delete().eq("id", id);
  if (error) throw error;
}

export async function uploadImage(userId, file) {
  if (!isConfigured) return URL.createObjectURL(file);
  const ext = file.name.split(".").pop();
  const path = `${userId}/${Date.now()}.${ext}`;
  const { error } = await supabase.storage.from("media").upload(path, file);
  if (error) throw error;
  return supabase.storage.from("media").getPublicUrl(path).data.publicUrl;
}

// ---------- ACTIONS (like / retweet / bookmark / follow) ----------
async function toggle(table, userId, tweetId, on) {
  if (!isConfigured) {
    const t = MOCK_TWEETS.find((x) => x.id === tweetId);
    if (t) {
      if (table === "likes") {
        t.liked = on;
        t.like_count += on ? 1 : -1;
      } else if (table === "retweets") {
        t.retweeted = on;
        t.retweet_count += on ? 1 : -1;
      } else if (table === "bookmarks") {
        t.bookmarked = on;
      }
    }
    return;
  }
  if (on) {
    const { error } = await supabase
      .from(table)
      .insert({ user_id: userId, tweet_id: tweetId });
    if (error && error.code !== "23505") throw error;
  } else {
    const { error } = await supabase
      .from(table)
      .delete()
      .match({ user_id: userId, tweet_id: tweetId });
    if (error) throw error;
  }
}

export const setLike = (userId, tweetId, on) =>
  toggle("likes", userId, tweetId, on);
export const setRetweet = (userId, tweetId, on) =>
  toggle("retweets", userId, tweetId, on);
export const setBookmark = (userId, tweetId, on) =>
  toggle("bookmarks", userId, tweetId, on);

export async function setFollow(followerId, followingId, on) {
  if (!isConfigured) {
    if (on) MOCK_FOLLOWS.add(followingId);
    else MOCK_FOLLOWS.delete(followingId);
    return;
  }
  if (on) {
    const { error } = await supabase
      .from("follows")
      .insert({ follower_id: followerId, following_id: followingId });
    if (error && error.code !== "23505") throw error;
  } else {
    const { error } = await supabase
      .from("follows")
      .delete()
      .match({ follower_id: followerId, following_id: followingId });
    if (error) throw error;
  }
}

// ---------- PROFILE ----------
export async function fetchProfile(username) {
  if (!isConfigured) {
    const profile = Object.values(MOCK_PROFILES).find(
      (p) => p.username.toLowerCase() === username.toLowerCase(),
    );
    if (profile) return profile;
    // Default fallback mock profile for any custom user
    return {
      id: "user-" + username,
      username,
      display_name: username.charAt(0).toUpperCase() + username.slice(1),
      avatar_url: null,
      verified: false,
      bio: `Hello! I am @${username} on Gather.`,
      created_at: new Date().toISOString(),
      follower_count: 10,
      following_count: 5,
    };
  }
  const { data, error } = await supabase
    .from("profiles")
    .select(
      `*, follower_count:follows!follows_following_id_fkey(count), following_count:follows!follows_follower_id_fkey(count)`,
    )
    .eq("username", username)
    .single();
  if (error) throw error;
  return {
    ...data,
    follower_count: data.follower_count?.[0]?.count ?? 0,
    following_count: data.following_count?.[0]?.count ?? 0,
  };
}

export async function isFollowing(followerId, followingId) {
  if (!isConfigured) return MOCK_FOLLOWS.has(followingId);
  const { data } = await supabase
    .from("follows")
    .select("follower_id")
    .match({ follower_id: followerId, following_id: followingId })
    .maybeSingle();
  return Boolean(data);
}

export async function fetchProfileTweets(profileId, tab, userId) {
  if (!isConfigured) {
    let list = MOCK_TWEETS.filter(
      (t) => t.user_id === profileId || (tab === "likes" && t.liked),
    );
    if (tab === "replies") list = list.filter((t) => t.reply_to);
    if (tab === "tweets") list = list.filter((t) => !t.reply_to);
    if (tab === "media") list = list.filter((t) => t.image_url || t.media?.length);
    return list.map((tweet) => ({ tweet: withTagEntities(tweet) }));
  }

  if (tab === "likes") {
    const { data, error } = await supabase
      .from("likes")
      .select(`created_at, tweet:tweets (${TWEET_FIELDS})`)
      .eq("user_id", profileId)
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) throw error;
    const tweets = (data || [])
      .filter((r) => r.tweet)
      .map((r) => withTagEntities(shapeTweet(r.tweet)));
    const withState = await attachUserState(tweets, userId);
    return filterTweetsBySafety(withState, await fetchSafetyFilters(userId)).map((tweet) => ({ tweet }));
  }

  let q = supabase
    .from("tweets")
    .select(TWEET_FIELDS)
    .eq("user_id", profileId)
    .eq("status", "published")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(50);
  q =
    tab === "replies"
      ? q.not("reply_to", "is", null)
      : tab === "media"
        ? q
        : q.is("reply_to", null);
  const { data, error } = await q;
  if (error) throw error;

  let items = (data || []).map((t) => ({
    sortAt: t.created_at,
    tweet: withTagEntities(shapeTweet(t)),
  }));

  if (tab === "media") {
    items = items.filter((item) => item.tweet.image_url || item.tweet.media?.length);
  }

  if (tab === "tweets") {
    const { data: rts } = await supabase
      .from("retweets")
      .select(
        `created_at, retweeter:profiles!retweets_user_id_fkey (id, username, display_name), tweet:tweets (${TWEET_FIELDS})`,
      )
      .eq("user_id", profileId)
      .order("created_at", { ascending: false })
      .limit(20);
    items = [
      ...items,
      ...(rts || [])
        .filter((r) => r.tweet)
        .map((r) => ({
          sortAt: r.created_at,
          retweetedBy: r.retweeter,
          tweet: withTagEntities(shapeTweet(r.tweet)),
        })),
    ].sort((a, b) => new Date(b.sortAt) - new Date(a.sortAt));
  }

  const withState = await attachUserState(
    items.map((i) => i.tweet),
    userId,
  );
  const filteredTweets = filterTweetsBySafety(withState, await fetchSafetyFilters(userId));
  return items
    .map((item, i) => ({ ...item, tweet: withState[i] }))
    .filter((item) => filteredTweets.some((tweet) => tweet.id === item.tweet.id));
}

export async function updateProfile(userId, fields) {
  if (!isConfigured) {
    if (MOCK_PROFILES[userId]) {
      Object.assign(MOCK_PROFILES[userId], fields);
    }
    return;
  }
  const { error } = await supabase
    .from("profiles")
    .update(fields)
    .eq("id", userId);
  if (error) throw error;
}

// ---------- BOOKMARKS ----------
export async function fetchBookmarks(userId) {
  if (!isConfigured) {
    return MOCK_TWEETS.filter((t) => t.bookmarked);
  }
  const { data, error } = await supabase
    .from("bookmarks")
    .select(`created_at, tweet:tweets (${TWEET_FIELDS})`)
    .eq("user_id", userId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  const tweets = (data || [])
    .filter((r) => r.tweet)
    .map((r) => shapeTweet(r.tweet));
  return attachUserState(filterTweetsBySafety(tweets, await fetchSafetyFilters(userId)), userId);
}

// ---------- SEARCH & TRENDS ----------
export async function searchTweets(query, userId) {
  if (!isConfigured) {
    const q = query.toLowerCase();
    const results = MOCK_TWEETS.filter(
      (t) =>
        t.status !== "draft" &&
        !t.deleted_at &&
        (t.content.toLowerCase().includes(q) ||
          (q.startsWith("#") && (t.hashtags || []).includes(q.slice(1)))),
    );
    return filterTweetsBySafety(results.map(withTagEntities), await fetchSafetyFilters(userId));
  }
  if (query.startsWith("#")) {
    const tag = query.slice(1).toLowerCase();
    const tagRows = await fetchTagRowsByNames([tag]);
    if (tagRows.length === 0) return [];
    const { data, error } = await supabase
      .from("post_tags")
      .select(`tweet:tweets (${TWEET_FIELDS})`)
      .eq("tag_id", tagRows[0].id)
      .order("created_at", { ascending: false })
      .limit(30);
    if (error) throw error;
    const safety = await fetchSafetyFilters(userId);
    return attachUserState(
      (data || [])
        .filter((row) => row.tweet)
        .map((row) => withTagEntities(shapeTweet(row.tweet)))
        .filter((tweet) => !safety.mutedAccountIds.has(tweet.user_id || tweet.author?.id))
        .filter((tweet) => !tweetContainsMutedWord(tweet, safety.mutedWords)),
      userId,
    );
  }
  const { data, error } = await supabase
    .from("tweets")
    .select(TWEET_FIELDS)
    .eq("status", "published")
    .is("deleted_at", null)
    .ilike("content", `%${query}%`)
    .order("created_at", { ascending: false })
    .limit(30);
  if (error) throw error;
  return attachUserState(
    filterTweetsBySafety((data || []).map((row) => withTagEntities(shapeTweet(row))), await fetchSafetyFilters(userId)),
    userId,
  );
}

export async function fetchTag(normalizedName, userId) {
  const cleaned = normalizedName.replace(/^#/, "").toLowerCase();
  if (!isConfigured) {
    const tag = getMockTagRecords().find(
      (item) => item.normalized_name === cleaned,
    );
    if (!tag) throw new Error("Tag not found");
    return {
      ...tag,
      is_following: MOCK_TAG_FOLLOWS.has(cleaned),
    };
  }
  const { data, error } = await supabase
    .from("tags")
    .select("*")
    .eq("normalized_name", cleaned)
    .single();
  if (error) throw error;
  const { data: follow } = await supabase
    .from("user_tag_follows")
    .select("user_id")
    .match({ user_id: userId, tag_id: data.id })
    .maybeSingle();
  return {
    ...data,
    is_following: Boolean(follow),
  };
}

export async function fetchTagPosts(tagName, userId, tab = "latest") {
  const cleaned = tagName.replace(/^#/, "").toLowerCase();
  if (!isConfigured) {
    let tweets = MOCK_TWEETS.filter((tweet) =>
      (tweet.hashtags || []).includes(cleaned),
    );
    if (tab === "media")
      tweets = tweets.filter((tweet) => tweet.image_url || tweet.media?.length);
    tweets = [...tweets].sort((a, b) => {
      if (tab === "top") {
        const scoreA =
          (a.like_count || 0) +
          (a.retweet_count || 0) * 2 +
          (a.reply_count || 0);
        const scoreB =
          (b.like_count || 0) +
          (b.retweet_count || 0) * 2 +
          (b.reply_count || 0);
        return (
          scoreB - scoreA || new Date(b.created_at) - new Date(a.created_at)
        );
      }
      return new Date(b.created_at) - new Date(a.created_at);
    });
    return filterTweetsBySafety(tweets.map(withTagEntities), await fetchSafetyFilters(userId)).map((tweet) => ({ tweet }));
  }

  const tagRows = await fetchTagRowsByNames([cleaned]);
  if (tagRows.length === 0) return [];

  const { data, error } = await supabase
    .from("post_tags")
    .select(`tweet:tweets (${TWEET_FIELDS})`)
    .eq("tag_id", tagRows[0].id)
    .limit(50);
  if (error) throw error;

  let tweets = (data || [])
    .filter((row) => row.tweet)
    .map((row) => withTagEntities(shapeTweet(row.tweet)));
  if (tab === "media")
    tweets = tweets.filter((tweet) => tweet.image_url || tweet.media?.length);
  tweets = [...tweets].sort((a, b) => {
    if (tab === "top") {
      const scoreA =
        (a.like_count || 0) + (a.retweet_count || 0) * 2 + (a.reply_count || 0);
      const scoreB =
        (b.like_count || 0) + (b.retweet_count || 0) * 2 + (b.reply_count || 0);
      return scoreB - scoreA || new Date(b.created_at) - new Date(a.created_at);
    }
    return new Date(b.created_at) - new Date(a.created_at);
  });
  const withState = await attachUserState(tweets, userId);
  return filterTweetsBySafety(withState, await fetchSafetyFilters(userId)).map((tweet) => ({ tweet }));
}

export async function fetchNotificationSettings(userId) {
  if (!userId) return DEFAULT_NOTIFICATION_SETTINGS;
  return {
    ...DEFAULT_NOTIFICATION_SETTINGS,
    ...readStoredJson(getPreferenceKey(userId, "notification-settings"), DEFAULT_NOTIFICATION_SETTINGS),
  };
}

export async function updateNotificationSettings(userId, nextSettings) {
  const merged = {
    ...DEFAULT_NOTIFICATION_SETTINGS,
    ...nextSettings,
  };
  writeStoredJson(getPreferenceKey(userId, "notification-settings"), merged);
  return merged;
}

export async function fetchRelatedTags(tagName) {
  const cleaned = tagName.replace(/^#/, "").toLowerCase();
  if (!isConfigured) {
    const relatedCounts = new Map();
    for (const tweet of MOCK_TWEETS.filter((item) =>
      (item.hashtags || []).includes(cleaned),
    )) {
      for (const other of tweet.hashtags || []) {
        if (other !== cleaned)
          relatedCounts.set(other, (relatedCounts.get(other) || 0) + 1);
      }
    }
    return [...relatedCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([normalized_name, post_count]) => ({
        id: `tag-${normalized_name}`,
        name: normalized_name,
        normalized_name,
        post_count,
      }));
  }

  const { data: baseTag, error: tagError } = await supabase
    .from("tags")
    .select("id")
    .eq("normalized_name", cleaned)
    .single();
  if (tagError) return [];

  const { data: coTags, error } = await supabase
    .from("post_tags")
    .select("post_id")
    .eq("tag_id", baseTag.id);
  if (error || !coTags?.length) return [];

  const postIds = coTags.map((row) => row.post_id);
  const { data: relatedRows, error: relatedError } = await supabase
    .from("post_tags")
    .select(
      "tag:tags!post_tags_tag_id_fkey (id, name, normalized_name, post_count)",
    )
    .in("post_id", postIds)
    .limit(200);
  if (relatedError) return [];

  const counts = new Map();
  for (const row of relatedRows || []) {
    const tag = row.tag;
    if (!tag || tag.normalized_name === cleaned) continue;
    counts.set(tag.normalized_name, {
      ...tag,
      score: (counts.get(tag.normalized_name)?.score || 0) + 1,
    });
  }
  return [...counts.values()].sort((a, b) => b.score - a.score).slice(0, 5);
}

export async function fetchFollowingTags(userId) {
  if (!isConfigured) {
    return getMockTagRecords().filter((tag) =>
      MOCK_TAG_FOLLOWS.has(tag.normalized_name),
    );
  }
  const { data, error } = await supabase
    .from("user_tag_follows")
    .select(
      "created_at, show_in_home, notify_popular, notify_breaking, tag:tags!user_tag_follows_tag_id_fkey (*)",
    )
    .eq("user_id", userId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data || []).map((row) => ({
    ...row.tag,
    follow_created_at: row.created_at,
    show_in_home: row.show_in_home,
  }));
}

export async function setTagFollow(userId, tag, on) {
  const normalizedName = String(tag).replace(/^#/, "").toLowerCase();
  if (!normalizedName) return;
  if (!isConfigured) {
    if (on) MOCK_TAG_FOLLOWS.add(normalizedName);
    else MOCK_TAG_FOLLOWS.delete(normalizedName);
    return;
  }

  const { data: tagRow, error: tagError } = await supabase
    .from("tags")
    .upsert(
      { name: normalizedName, normalized_name: normalizedName },
      { onConflict: "normalized_name" },
    )
    .select("id")
    .single();
  if (tagError) throw tagError;

  if (on) {
    const { error } = await supabase
      .from("user_tag_follows")
      .upsert(
        { user_id: userId, tag_id: tagRow.id },
        { onConflict: "user_id,tag_id" },
      );
    if (error) throw error;
  } else {
    const { error } = await supabase
      .from("user_tag_follows")
      .delete()
      .match({ user_id: userId, tag_id: tagRow.id });
    if (error) throw error;
  }
}

export async function isFollowingTag(userId, tag) {
  const normalizedName = String(tag).replace(/^#/, "").toLowerCase();
  if (!isConfigured) return MOCK_TAG_FOLLOWS.has(normalizedName);
  const { data: tagRow } = await supabase
    .from("tags")
    .select("id")
    .eq("normalized_name", normalizedName)
    .maybeSingle();
  if (!tagRow) return false;
  const { data } = await supabase
    .from("user_tag_follows")
    .select("user_id")
    .match({ user_id: userId, tag_id: tagRow.id })
    .maybeSingle();
  return Boolean(data);
}

export async function searchUsers(query) {
  if (!isConfigured) {
    const q = query.toLowerCase();
    return Object.values(MOCK_PROFILES).filter(
      (p) => p.username.includes(q) || p.display_name.toLowerCase().includes(q),
    );
  }
  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .or(`username.ilike.%${query}%,display_name.ilike.%${query}%`)
    .limit(10);
  if (error) throw error;
  return data || [];
}

export async function fetchTrends() {
  if (!isConfigured) {
    return [
      { tag: "react", tweet_count: 14200 },
      { tag: "vite", tweet_count: 8900 },
      { tag: "ai", tweet_count: 45200 },
      { tag: "webdev", tweet_count: 12300 },
    ];
  }
  try {
    const { data, error } = await supabase.rpc("get_trends");
    if (error) return [];
    return data || [];
  } catch {
    return [];
  }
}

export async function fetchWhoToFollow(userId) {
  if (!isConfigured) {
    return Object.values(MOCK_PROFILES).filter(
      (p) => p.id !== userId && !MOCK_FOLLOWS.has(p.id),
    );
  }
  try {
    const { data: follows } = await supabase
      .from("follows")
      .select("following_id")
      .eq("follower_id", userId);
    const exclude = [userId, ...(follows || []).map((r) => r.following_id)];
    const { data } = await supabase
      .from("profiles")
      .select("*")
      .not("id", "in", `(${exclude.join(",")})`)
      .order("created_at", { ascending: false })
      .limit(3);
    return data || [];
  } catch {
    return [];
  }
}

// ---------- NOTIFICATIONS ----------
export async function fetchNotifications(userId, tab = "all") {
  if (!isConfigured) {
    const all = MOCK_NOTIFICATIONS.filter((n) => n.user_id === userId);
    if (tab === "mentions") return all.filter((n) => n.type === "reply");
    if (tab === "verified") return all.filter((n) => n.actor?.verified);
    return all;
  }

  let query = supabase
    .from("notifications")
    .select(
      `*, actor:profiles!notifications_actor_id_fkey (id, username, display_name, avatar_url, verified), tweet:tweets (id, content)`,
    )
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(50);

  if (tab === "mentions") {
    query = query.eq("type", "reply");
  }

  const { data, error } = await query;
  if (error) throw error;

  if (tab === "verified") {
    return (data || []).filter((n) => n.actor?.verified);
  }
  return data || [];
}

export async function fetchMutedWords(userId) {
  if (!userId) return [];
  if (!isConfigured) return [...MOCK_MUTED_WORDS];
  const { data, error } = await supabase
    .from("muted_keywords")
    .select("id, phrase")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function addMutedWord(userId, phrase) {
  const cleaned = String(phrase || "").trim().toLowerCase();
  if (!cleaned) return null;
  if (!isConfigured) {
    if (!MOCK_MUTED_WORDS.includes(cleaned)) MOCK_MUTED_WORDS.unshift(cleaned);
    return { id: cleaned, phrase: cleaned };
  }
  const { data, error } = await supabase
    .from("muted_keywords")
    .insert({ user_id: userId, phrase: cleaned })
    .select("id, phrase")
    .single();
  if (error) throw error;
  return data;
}

export async function removeMutedWord(userId, mutedWordIdOrPhrase) {
  if (!isConfigured) {
    MOCK_MUTED_WORDS = MOCK_MUTED_WORDS.filter((word) => word !== mutedWordIdOrPhrase);
    return;
  }
  const value = String(mutedWordIdOrPhrase);
  const { error } = await supabase
    .from("muted_keywords")
    .delete()
    .or(`id.eq.${value},phrase.eq.${value}`)
    .eq("user_id", userId);
  if (error) throw error;
}

export async function setAccountMute(userId, targetId, on) {
  if (!isConfigured) {
    if (on) MOCK_MUTED_ACCOUNT_IDS.add(targetId);
    else MOCK_MUTED_ACCOUNT_IDS.delete(targetId);
    return;
  }
  if (on) {
    const { error } = await supabase
      .from("account_mutes")
      .upsert({ muter_id: userId, muted_id: targetId }, { onConflict: "muter_id,muted_id" });
    if (error) throw error;
  } else {
    const { error } = await supabase
      .from("account_mutes")
      .delete()
      .match({ muter_id: userId, muted_id: targetId });
    if (error) throw error;
  }
}

export async function reportTweet(userId, tweetId, reason = "spam", details = "") {
  if (!isConfigured) return { id: `report-${tweetId}` };
  const { data, error } = await supabase
    .from("content_reports")
    .insert({ reporter_id: userId, tweet_id: tweetId, reason, details })
    .select("id")
    .single();
  if (error) throw error;
  return data;
}

export async function markNotificationsRead(userId) {
  if (!isConfigured) {
    MOCK_NOTIFICATIONS.forEach((n) => {
      n.read = true;
    });
    return;
  }
  const { error } = await supabase
    .from("notifications")
    .update({ read: true })
    .eq("user_id", userId)
    .eq("read", false);
  if (error) throw error;
}

export async function fetchUnreadCounts(userId) {
  if (!isConfigured) {
    const n = MOCK_NOTIFICATIONS.filter((x) => !x.read).length;
    const m = MOCK_MESSAGES.filter(
      (x) => x.recipient_id === userId && !x.read,
    ).length;
    return { notifications: n, messages: m };
  }
  try {
    const [n, m] = await Promise.all([
      supabase
        .from("notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .eq("read", false),
      supabase
        .from("messages")
        .select("id", { count: "exact", head: true })
        .eq("recipient_id", userId)
        .eq("read", false),
    ]);
    return { notifications: n.count || 0, messages: m.count || 0 };
  } catch {
    return { notifications: 0, messages: 0 };
  }
}

// ---------- MESSAGES ----------
export async function fetchConversations(userId) {
  if (!isConfigured) {
    const followingSet = new Set([...MOCK_FOLLOWS]);
    const sorted = [...MOCK_MESSAGES].sort(
      (a, b) => new Date(b.created_at) - new Date(a.created_at),
    );
    const convos = new Map();
    for (const msg of sorted) {
      const other = msg.sender_id === userId ? msg.recipient : msg.sender;
      if (!other) continue;
      if (!convos.has(other.id)) {
        convos.set(other.id, {
          other,
          lastMessage: msg,
          unread: 0,
          hasOutgoing: false,
          kind: "direct",
        });
      }
      if (msg.sender_id === userId) convos.get(other.id).hasOutgoing = true;
      if (msg.recipient_id === userId && !msg.read)
        convos.get(other.id).unread++;
    }
    return [...convos.values()].map((conversation) => {
      const isDirect =
        conversation.hasOutgoing || followingSet.has(conversation.other.id);
      return {
        ...conversation,
        kind: isDirect ? "direct" : "request",
      };
    });
  }
  const { data: followsData, error: followsError } = await supabase
    .from("follows")
    .select("following_id")
    .eq("follower_id", userId);
  if (followsError) throw followsError;
  const followingSet = new Set(
    (followsData || []).map((row) => row.following_id),
  );

  const { data, error } = await supabase
    .from("messages")
    .select(
      `*, sender:profiles!messages_sender_id_fkey (id, username, display_name, avatar_url), recipient:profiles!messages_recipient_id_fkey (id, username, display_name, avatar_url)`,
    )
    .or(`sender_id.eq.${userId},recipient_id.eq.${userId}`)
    .order("created_at", { ascending: false })
    .limit(500);
  if (error) throw error;
  const convos = new Map();
  for (const msg of data || []) {
    const other = msg.sender_id === userId ? msg.recipient : msg.sender;
    if (!other) continue;
    if (!convos.has(other.id)) {
      convos.set(other.id, {
        other,
        lastMessage: msg,
        unread: 0,
        hasOutgoing: false,
        kind: "direct",
      });
    }
    if (msg.sender_id === userId) convos.get(other.id).hasOutgoing = true;
    if (msg.recipient_id === userId && !msg.read) convos.get(other.id).unread++;
  }
  return [...convos.values()].map((conversation) => {
    const isDirect =
      conversation.hasOutgoing || followingSet.has(conversation.other.id);
    return {
      ...conversation,
      kind: isDirect ? "direct" : "request",
    };
  });
}

export async function fetchThread(userId, otherId) {
  if (!isConfigured) {
    return MOCK_MESSAGES.filter(
      (m) =>
        (m.sender_id === userId && m.recipient_id === otherId) ||
        (m.sender_id === otherId && m.recipient_id === userId),
    );
  }
  const { data, error } = await supabase
    .from("messages")
    .select("*")
    .or(
      `and(sender_id.eq.${userId},recipient_id.eq.${otherId}),and(sender_id.eq.${otherId},recipient_id.eq.${userId})`,
    )
    .order("created_at", { ascending: true })
    .limit(200);
  if (error) throw error;
  return data || [];
}

export async function sendMessage(senderId, recipientId, content) {
  if (!isConfigured) {
    const sender = MOCK_PROFILES[senderId] || MOCK_PROFILES["demo-user-id"];
    const recipient = MOCK_PROFILES[recipientId] || MOCK_PROFILES["user-sarah"];
    const newMsg = {
      id: "msg-" + Date.now(),
      sender_id: senderId,
      recipient_id: recipientId,
      content,
      created_at: new Date().toISOString(),
      read: false,
      sender,
      recipient,
    };
    MOCK_MESSAGES.push(newMsg);
    return newMsg;
  }
  const { data, error } = await supabase
    .from("messages")
    .insert({ sender_id: senderId, recipient_id: recipientId, content })
    .select("*")
    .single();
  if (error) throw error;
  return data;
}

export async function markThreadRead(userId, otherId) {
  if (!isConfigured) {
    MOCK_MESSAGES.forEach((m) => {
      if (m.recipient_id === userId && m.sender_id === otherId) m.read = true;
    });
    return;
  }
  const { error } = await supabase
    .from("messages")
    .update({ read: true })
    .eq("recipient_id", userId)
    .eq("sender_id", otherId)
    .eq("read", false);
  if (error) throw error;
}

export function subscribeToMessages(userId, onMessage) {
  if (!isConfigured || !supabase) return () => {};
  try {
    const channel = supabase
      .channel(`messages-${userId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "messages",
          filter: `recipient_id=eq.${userId}`,
        },
        (payload) => onMessage(payload.new),
      )
      .subscribe();
    return () => supabase.removeChannel(channel);
  } catch {
    return () => {};
  }
}

export function subscribeToNotifications(userId, onNotification) {
  if (!isConfigured || !supabase) return () => {};
  try {
    const channel = supabase
      .channel(`notifications-${userId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "notifications",
          filter: `user_id=eq.${userId}`,
        },
        (payload) => onNotification(payload.new),
      )
      .subscribe();
    return () => supabase.removeChannel(channel);
  } catch {
    return () => {};
  }
}
