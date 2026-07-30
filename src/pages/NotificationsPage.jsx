import { useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { fetchNotifications, markNotificationsRead } from '../lib/api'
import { PageHeader, Spinner, EmptyState } from '../components/Shared'
import Avatar from '../components/Avatar'
import Icon from '../components/Icons'
import { Link } from 'react-router-dom'
import { timeAgo } from '../lib/format'
import { useUi } from '../context/UiContext'

export default function NotificationsPage() {
  const { user } = useAuth()
  const { refreshUnread } = useUi()
  const [notifications, setNotifications] = useState([])
  const [loading, setLoading] = useState(true)
  const [tab, setTab] = useState('all')
  const [loadError, setLoadError] = useState(false)

  useEffect(() => {
    if (!user) return
    setLoadError(false)
    fetchNotifications(user.id)
      .then(data => setNotifications(data))
      .catch(() => setLoadError(true))
      .finally(() => setLoading(false))
    markNotificationsRead(user.id)
      .then(() => refreshUnread())
      .catch(() => {})
  }, [user, refreshUnread])

  return (
    <div>
      <PageHeader title="Notifications" />
      <div className="tabs">
        <button className={`tab ${tab === 'all' ? 'active' : ''}`} onClick={() => setTab('all')}>
          <span>All</span>
        </button>
        <button className={`tab ${tab === 'verified' ? 'active' : ''}`} onClick={() => setTab('verified')}>
          <span>Verified</span>
        </button>
        <button className={`tab ${tab === 'mentions' ? 'active' : ''}`} onClick={() => setTab('mentions')}>
          <span>Mentions</span>
        </button>
      </div>

      {loading ? (
        <Spinner />
      ) : loadError ? (
        <EmptyState title="Couldn’t load notifications" text="Please try again in a moment." />
      ) : notifications.length === 0 ? (
        <EmptyState title="Nothing to see here — yet" text="From likes to Retweets and a whole lot more, this is where all the action about your Tweets and account will happen." />
      ) : (
        notifications.map((n) => (
          <div key={n.id} className={`notification-item ${!n.read ? 'unread' : ''}`}>
            <div className="notification-icon">
              {n.type === 'like' && <Icon name="heartFilled" size={22} style={{ color: '#f4212e' }} />}
              {n.type === 'retweet' && <Icon name="retweet" size={22} style={{ color: '#00ba7c' }} />}
              {n.type === 'follow' && <Icon name="userFilled" size={22} className="blue" />}
              {n.type === 'reply' && <Icon name="reply" size={22} className="blue" />}
            </div>
            <div className="notification-body">
              <div style={{ marginBottom: 4 }}>
                <Avatar profile={n.actor} size={32} />
              </div>
              <div>
                <Link to={`/${n.actor?.username}`} className="bold">
                  {n.actor?.display_name || n.actor?.username}
                </Link>{' '}
                {n.type === 'like' && 'liked your Tweet'}
                {n.type === 'retweet' && 'retweeted your Tweet'}
                {n.type === 'follow' && 'followed you'}
                {n.type === 'reply' && 'replied to your Tweet'}
                <span className="muted small" style={{ marginLeft: 8 }}>{timeAgo(n.created_at)}</span>
              </div>
              {n.tweet && (
                <div className="muted" style={{ marginTop: 4, fontSize: 14 }}>
                  {n.tweet.content}
                </div>
              )}
            </div>
          </div>
        ))
      )}
    </div>
  )
}
