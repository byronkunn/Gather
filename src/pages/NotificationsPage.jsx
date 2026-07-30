import { useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { fetchNotificationSettings, fetchNotifications, markNotificationsRead, updateNotificationSettings } from '../lib/api'
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
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [settings, setSettings] = useState(null)

  useEffect(() => {
    if (!user) return
    fetchNotificationSettings(user.id).then(setSettings).catch(() => {})
  }, [user])

  useEffect(() => {
    if (!user) return
    setLoadError(false)
    setLoading(true)
    fetchNotifications(user.id, tab)
      .then(data => setNotifications(data))
      .catch(() => setLoadError(true))
      .finally(() => setLoading(false))
  }, [user, tab])

  useEffect(() => {
    if (!user) return
    markNotificationsRead(user.id)
      .then(() => refreshUnread())
      .catch(() => {})
  }, [user, refreshUnread])

  const updateSetting = async (key, value) => {
    const next = await updateNotificationSettings(user.id, { ...settings, [key]: value })
    setSettings(next)
  }

  const visibleNotifications = notifications.filter((n) => {
    if (!settings) return true
    if (settings.verifiedOnly && !n.actor?.verified) return false
    if (n.type === 'like') return settings.likes
    if (n.type === 'retweet' || n.type === 'quote') return settings.reposts
    if (n.type === 'follow') return settings.follows
    if (n.type === 'reply') return settings.replies
    if (n.type === 'mention') return settings.mentions
    return true
  })

  return (
    <div>
      <PageHeader title="Notifications">
        <button className="icon-btn" aria-label="Notification settings" onClick={() => setSettingsOpen((open) => !open)}>
          <Icon name="settings" size={18} />
        </button>
      </PageHeader>
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
      {settingsOpen && settings && (
        <div className="notification-settings-panel">
          <div className="section-label">Notification filters</div>
          {[
            ['likes', 'Likes'],
            ['reposts', 'Reposts and quotes'],
            ['follows', 'Follows'],
            ['replies', 'Replies'],
            ['mentions', 'Mentions'],
            ['verifiedOnly', 'Only from verified accounts'],
          ].map(([key, label]) => (
            <label key={key} className="notification-setting-row">
              <span>{label}</span>
              <input type="checkbox" checked={Boolean(settings[key])} onChange={(e) => updateSetting(key, e.target.checked)} />
            </label>
          ))}
        </div>
      )}

      {loading ? (
        <Spinner />
      ) : loadError ? (
        <EmptyState title="Couldn’t load notifications" text="Please try again in a moment." />
      ) : visibleNotifications.length === 0 ? (
        <EmptyState
          title={tab === 'verified' ? 'No verified notifications yet' : tab === 'mentions' ? 'No mentions yet' : 'Nothing to see here — yet'}
          text={tab === 'all' ? 'From likes to Retweets and a whole lot more, this is where all the action about your Tweets and account will happen.' : 'When there is activity in this tab, it will show up here.'}
        />
      ) : (
        visibleNotifications.map((n) => (
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
                {n.actor?.verified && <Icon name="verified" size={15} className="blue" style={{ marginRight: 4, verticalAlign: 'text-bottom' }} />}
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
