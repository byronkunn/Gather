import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { fetchTweet, fetchReplies } from '../lib/api'
import Tweet, { TweetText } from '../components/Tweet'
import TweetComposer from '../components/TweetComposer'
import Avatar from '../components/Avatar'
import { Spinner, PageHeader } from '../components/Shared'
import { fullTime, compact } from '../lib/format'
import { setLike, setRetweet, setBookmark } from '../lib/api'
import Icon from '../components/Icons'
import { useUi } from '../context/UiContext'

export default function TweetDetail() {
  const { id } = useParams()
  const { user } = useAuth()
  const { openCompose } = useUi()
  const [tweet, setTweet] = useState(null)
  const [parent, setParent] = useState(null)
  const [replies, setReplies] = useState(null)
  const [notFound, setNotFound] = useState(false)

  const load = useCallback(async () => {
    try {
      const t = await fetchTweet(id, user.id)
      setTweet(t)
      if (t.reply_to) {
        fetchTweet(t.reply_to, user.id).then(setParent).catch(() => {})
      } else {
        setParent(null)
      }
      setReplies(await fetchReplies(id, user.id))
    } catch {
      setNotFound(true)
    }
  }, [id, user.id])

  useEffect(() => {
    setTweet(null)
    setReplies(null)
    setNotFound(false)
    load()
  }, [load])

  if (notFound) {
    return (
      <div>
        <PageHeader title="Tweet" back />
        <div className="empty-state"><h2>This Tweet doesn't exist</h2></div>
      </div>
    )
  }

  if (!tweet) return (<div><PageHeader title="Tweet" back /><Spinner /></div>)

  return (
    <div>
      <PageHeader title="Tweet" back />
      {parent && <Tweet item={parent} />}
      <FocusedTweet tweet={tweet} onAction={load} openCompose={openCompose} userId={user.id} />
      <div className="detail-composer">
        <TweetComposer replyTo={tweet} onPosted={load} />
      </div>
      {replies === null ? (
        <Spinner />
      ) : (
        replies.map((r) => <Tweet key={r.id} item={r} onDeleted={load} />)
      )}
    </div>
  )
}

function FocusedTweet({ tweet, onAction, openCompose, userId }) {
  const [liked, setLiked] = useState(tweet.liked)
  const [likeCount, setLikeCount] = useState(tweet.like_count)
  const [retweeted, setRetweeted] = useState(tweet.retweeted)
  const [rtCount, setRtCount] = useState(tweet.retweet_count)
  const [bookmarked, setBookmarked] = useState(tweet.bookmarked)

  useEffect(() => {
    setLiked(tweet.liked); setLikeCount(tweet.like_count)
    setRetweeted(tweet.retweeted); setRtCount(tweet.retweet_count)
    setBookmarked(tweet.bookmarked)
  }, [tweet])

  const author = tweet.author

  const toggle = async (fn, on, setOn, setCount) => {
    setOn(on)
    setCount?.((c) => c + (on ? 1 : -1))
    try {
      await fn(userId, tweet.id, on)
    } catch {
      setOn(!on)
      setCount?.((c) => c + (on ? -1 : 1))
    }
  }

  return (
    <article className="tweet-focused">
      <div className="tweet-focused-header">
        <Link to={`/${author.username}`}>
          <Avatar profile={author} size={48} />
        </Link>
        <div>
          <Link to={`/${author.username}`} className="tweet-name">{author.display_name}</Link>
          <div className="muted">@{author.username}</div>
        </div>
      </div>
      <div className="tweet-focused-text">
        <TweetText text={tweet.content} />
      </div>
      {tweet.image_url && (
        <div className="tweet-image">
          <img src={tweet.image_url} alt="" />
        </div>
      )}
      <div className="tweet-focused-time muted">{fullTime(tweet.created_at)}</div>
      {(rtCount > 0 || likeCount > 0) && (
        <div className="tweet-focused-stats">
          {rtCount > 0 && (<span><strong>{compact(rtCount)}</strong> <span className="muted">Retweets</span></span>)}
          {likeCount > 0 && (<span><strong>{compact(likeCount)}</strong> <span className="muted">Likes</span></span>)}
        </div>
      )}
      <div className="tweet-actions tweet-focused-actions">
        <button className="action action-reply" onClick={() => openCompose(tweet)} aria-label="Reply">
          <span className="action-icon"><Icon name="reply" size={22} /></span>
        </button>
        <button
          className={`action action-retweet ${retweeted ? 'active' : ''}`}
          onClick={() => toggle(setRetweet, !retweeted, setRetweeted, setRtCount)}
          aria-label="Retweet"
        >
          <span className="action-icon"><Icon name="retweet" size={22} /></span>
        </button>
        <button
          className={`action action-like ${liked ? 'active' : ''}`}
          onClick={() => toggle(setLike, !liked, setLiked, setLikeCount)}
          aria-label="Like"
        >
          <span className="action-icon"><Icon name={liked ? 'heartFilled' : 'heart'} size={22} /></span>
        </button>
        <button
          className={`action action-bookmark ${bookmarked ? 'active' : ''}`}
          onClick={() => toggle(setBookmark, !bookmarked, setBookmarked, null)}
          aria-label="Bookmark"
        >
          <span className="action-icon"><Icon name={bookmarked ? 'bookmarkFilled' : 'bookmark'} size={22} /></span>
        </button>
      </div>
    </article>
  )
}
