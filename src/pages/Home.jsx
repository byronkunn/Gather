import { useCallback, useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { fetchFeed } from '../lib/api'
import Tweet from '../components/Tweet'
import TweetComposer from '../components/TweetComposer'
import { Spinner, EmptyState } from '../components/Shared'
import Avatar from '../components/Avatar'
import Icon from '../components/Icons'

export default function Home() {
  const { user, profile } = useAuth()
  const [tab, setTab] = useState('foryou')
  const [items, setItems] = useState(null)
  const [loadError, setLoadError] = useState(false)
  const [lastUpdated, setLastUpdated] = useState(null)

  const load = useCallback(async () => {
    setLoadError(false)
    try {
      setItems(await fetchFeed(user.id, tab))
      setLastUpdated(new Date())
    } catch {
      setItems([])
      setLoadError(true)
    }
  }, [user.id, tab])

  useEffect(() => {
    setItems(null)
    load()
  }, [load])

  const onPosted = () => load()
  const onDeleted = (id) => setItems((its) => its.filter((i) => i.tweet.id !== id))

  return (
    <div>
      <div className="page-header home-header">
        <div className="home-header-top">
          <div className="mobile-only home-avatar">
            <Avatar profile={profile} size={32} />
          </div>
          <div className="home-heading-wrap">
            <h1>Home</h1>
            <div className="muted small home-subtitle">
              {tab === 'following' ? 'People and tags you follow, newest first.' : 'A mix of popular and recent posts for you.'}
            </div>
          </div>
          <div className="home-header-actions">
            {lastUpdated && <span className="muted small">Updated just now</span>}
            <button className="btn btn-outline btn-inline" onClick={load}>Refresh</button>
            <Icon name="sparkle" size={20} className="blue home-sparkle" />
          </div>
        </div>
        <div className="tabs">
          <button className={`tab ${tab === 'foryou' ? 'active' : ''}`} onClick={() => setTab('foryou')}>
            <span>For you</span>
          </button>
          <button className={`tab ${tab === 'following' ? 'active' : ''}`} onClick={() => setTab('following')}>
            <span>Following</span>
          </button>
        </div>
      </div>
      <div className="desktop-composer">
        <TweetComposer onPosted={onPosted} />
      </div>
      {items === null ? (
        <Spinner />
      ) : loadError ? (
        <EmptyState title="Couldn’t load your timeline" text="Please try again in a moment." />
      ) : items.length === 0 ? (
        <EmptyState
          title="Welcome to Gather!"
          text={tab === 'following' ? 'Follow some people to see their Tweets here.' : 'This is the best place to see what’s happening. Post the first Tweet!'}
        />
      ) : (
        items.map((item, i) => (
          <Tweet key={`${item.tweet.id}-${item.retweetedBy?.id ?? 'o'}-${i}`} item={item} onDeleted={onDeleted} />
        ))
      )}
    </div>
  )
}
