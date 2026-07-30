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

  const load = useCallback(async () => {
    setLoadError(false)
    try {
      setItems(await fetchFeed(user.id, tab))
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
          <h1>Home</h1>
          <Icon name="sparkle" size={20} className="blue home-sparkle" />
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
          title="Welcome to Twitter!"
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
