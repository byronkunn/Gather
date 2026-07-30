import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { useUi } from '../context/UiContext'
import { setLike, setRetweet, setBookmark, deleteTweet, pinTweetOnProfile, clearPinnedTweet, reportTweet, setAccountMute } from '../lib/api'
import { timeAgo, compact } from '../lib/format'
import Avatar from './Avatar'
import Icon from './Icons'
import Modal from './Modal'

// Render tweet text with clickable #hashtags and @mentions
export function TweetText({ text }) {
  const parts = text.split(/(#\w+|@\w+|https?:\/\/\S+)/g)
  return (
    <span>
      {parts.map((part, i) => {
        if (/^#\w+$/.test(part)) {
          return (
            <Link key={i} className="link-blue" to={`/tags/${encodeURIComponent(part.slice(1).toLowerCase())}`} onClick={(e) => e.stopPropagation()}>
              {part}
            </Link>
          )
        }
        if (/^@\w+$/.test(part)) {
          return (
            <Link key={i} className="link-blue" to={`/${part.slice(1)}`} onClick={(e) => e.stopPropagation()}>
              {part}
            </Link>
          )
        }
        if (/^https?:\/\//.test(part)) {
          return (
            <a key={i} className="link-blue" href={part} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>
              {part.replace(/^https?:\/\//, '').slice(0, 30)}
            </a>
          )
        }
        return part
      })}
    </span>
  )
}

export default function Tweet({ item, onDeleted }) {
  const tweet = item.tweet ?? item
  const retweetedBy = item.retweetedBy
  const { user, profile, refreshProfile } = useAuth()
  const { openCompose } = useUi()
  const navigate = useNavigate()

  const [liked, setLiked] = useState(tweet.liked)
  const [likeCount, setLikeCount] = useState(tweet.like_count)
  const [retweeted, setRetweeted] = useState(tweet.retweeted)
  const [rtCount, setRtCount] = useState(tweet.retweet_count)
  const [bookmarked, setBookmarked] = useState(tweet.bookmarked)
  const [menuOpen, setMenuOpen] = useState(false)
  const [imageOpen, setImageOpen] = useState(false)

  const author = tweet.author
  const isOwnTweet = author.id === user?.id
  const isPinned = profile?.pinned_tweet_id === tweet.id

  const toggleLike = async (e) => {
    e.stopPropagation()
    const on = !liked
    setLiked(on)
    setLikeCount((c) => c + (on ? 1 : -1))
    try {
      await setLike(user.id, tweet.id, on)
    } catch {
      setLiked(!on)
      setLikeCount((c) => c + (on ? -1 : 1))
    }
  }

  const toggleRetweet = async (e) => {
    e.stopPropagation()
    const on = !retweeted
    setRetweeted(on)
    setRtCount((c) => c + (on ? 1 : -1))
    try {
      await setRetweet(user.id, tweet.id, on)
    } catch {
      setRetweeted(!on)
      setRtCount((c) => c + (on ? -1 : 1))
    }
  }

  const toggleBookmark = async (e) => {
    e.stopPropagation()
    const on = !bookmarked
    setBookmarked(on)
    try {
      await setBookmark(user.id, tweet.id, on)
    } catch {
      setBookmarked(!on)
    }
  }

  const remove = async (e) => {
    e.stopPropagation()
    setMenuOpen(false)
    if (!window.confirm('Delete Tweet?')) return
    await deleteTweet(tweet.id)
    onDeleted?.(tweet.id)
  }

  const togglePinned = async (e) => {
    e.stopPropagation()
    setMenuOpen(false)
    if (isPinned) {
      await clearPinnedTweet(user.id)
    } else {
      await pinTweetOnProfile(user.id, tweet.id)
    }
    refreshProfile?.()
  }

  const muteAuthor = async (e) => {
    e.stopPropagation()
    setMenuOpen(false)
    if (!window.confirm(`Mute @${author.username}? Their posts will be hidden from your feeds.`)) return
    await setAccountMute(user.id, author.id, true)
    onDeleted?.(tweet.id)
  }

  const reportPost = async (e) => {
    e.stopPropagation()
    setMenuOpen(false)
    const reason = window.prompt('Report reason (spam, harassment, sensitive, impersonation)', 'spam')
    if (!reason) return
    await reportTweet(user.id, tweet.id, reason.toLowerCase())
    window.alert('Thanks. Your report was submitted.')
  }

  const reply = (e) => {
    e.stopPropagation()
    openCompose(tweet)
  }

  const share = async (e) => {
    e.stopPropagation()
    const url = `${window.location.origin}/tweet/${tweet.id}`
    if (navigator.share) {
      navigator.share({ url }).catch(() => {})
    } else {
      await navigator.clipboard.writeText(url)
    }
  }

  if (!author) return null

  return (
    <article className="tweet" onClick={() => navigate(`/tweet/${tweet.id}`)}>
      {item.reasonTag && (
        <div className="tweet-context">
          <span>Because you follow</span>
          <Link to={`/tags/${item.reasonTag}`} className="link-blue" onClick={(e) => e.stopPropagation()}>
            #{item.reasonTag}
          </Link>
        </div>
      )}
      {retweetedBy && (
        <div className="tweet-context">
          <Icon name="retweet" size={16} />
          <span>{retweetedBy.id === user?.id ? 'You' : retweetedBy.display_name} Retweeted</span>
        </div>
      )}
      <div className="tweet-body">
        <Link to={`/${author.username}`} onClick={(e) => e.stopPropagation()} className="tweet-avatar">
          <Avatar profile={author} size={40} />
        </Link>
        <div className="tweet-content">
          <div className="tweet-header">
            <Link to={`/${author.username}`} onClick={(e) => e.stopPropagation()} className="tweet-name">
              {author.display_name}
            </Link>
            <span className="tweet-meta">@{author.username}</span>
            <span className="tweet-meta">·</span>
            <span className="tweet-meta" title={new Date(tweet.created_at).toLocaleString()}>
              {timeAgo(tweet.created_at)}
            </span>
            <div className="tweet-menu-wrap">
              <button
                className="icon-btn tweet-more"
                aria-label="More"
                onClick={(e) => {
                  e.stopPropagation()
                  setMenuOpen((o) => !o)
                }}
              >
                <Icon name="dots" size={18} />
              </button>
              {menuOpen && (
                <div className="dropdown" onClick={(e) => e.stopPropagation()}>
                  {isOwnTweet ? (
                    <>
                      <button className="dropdown-item" onClick={togglePinned}>{isPinned ? 'Unpin from profile' : 'Pin to profile'}</button>
                      <button className="dropdown-item danger" onClick={remove}>Delete</button>
                    </>
                  ) : (
                    <>
                      <button className="dropdown-item" onClick={muteAuthor}>Mute @{author.username}</button>
                      <button className="dropdown-item danger" onClick={reportPost}>Report post</button>
                    </>
                  )}
                </div>
              )}
            </div>
          </div>
          <div className="tweet-text">
            <TweetText text={tweet.content} />
          </div>
          {tweet.image_url && (
            <div
              className="tweet-image"
              onClick={(e) => {
                e.stopPropagation()
                setImageOpen(true)
              }}
            >
              <img src={tweet.image_url} alt="Tweet media" loading="lazy" />
            </div>
          )}
          <div className="tweet-actions">
            <button className="action action-reply" onClick={reply} aria-label="Reply">
              <span className="action-icon"><Icon name="reply" size={18} /></span>
              <span className="action-count">{tweet.reply_count > 0 && compact(tweet.reply_count)}</span>
            </button>
            <button className={`action action-retweet ${retweeted ? 'active' : ''}`} onClick={toggleRetweet} aria-label="Retweet">
              <span className="action-icon"><Icon name="retweet" size={18} /></span>
              <span className="action-count">{rtCount > 0 && compact(rtCount)}</span>
            </button>
            <button className={`action action-like ${liked ? 'active' : ''}`} onClick={toggleLike} aria-label="Like">
              <span className="action-icon"><Icon name={liked ? 'heartFilled' : 'heart'} size={18} /></span>
              <span className="action-count">{likeCount > 0 && compact(likeCount)}</span>
            </button>
            <button className={`action action-bookmark ${bookmarked ? 'active' : ''}`} onClick={toggleBookmark} aria-label="Bookmark">
              <span className="action-icon"><Icon name={bookmarked ? 'bookmarkFilled' : 'bookmark'} size={18} /></span>
            </button>
            <button className="action action-share" onClick={share} aria-label="Share">
              <span className="action-icon"><Icon name="share" size={18} /></span>
            </button>
          </div>
        </div>
      </div>
      {imageOpen && (
        <Modal onClose={() => setImageOpen(false)} className="media-modal">
          <div className="media-modal-body">
            <img src={tweet.image_url} alt="Tweet media" className="media-modal-image" />
          </div>
        </Modal>
      )}
    </article>
  )
}
