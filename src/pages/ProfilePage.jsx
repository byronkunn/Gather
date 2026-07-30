import { useEffect, useState, useCallback } from 'react'
import { useParams } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { fetchProfile, fetchProfileTweets, isFollowing } from '../lib/api'
import Tweet from '../components/Tweet'
import Avatar from '../components/Avatar'
import FollowButton from '../components/FollowButton'
import EditProfileModal from '../components/EditProfileModal'
import { PageHeader, Spinner, EmptyState } from '../components/Shared'
import { joinDate, normalizeExternalUrl } from '../lib/format'
import Icon from '../components/Icons'

export default function ProfilePage() {
  const { username } = useParams()
  const { user, profile: authProfile } = useAuth()
  const [profile, setProfile] = useState(null)
  const [tab, setTab] = useState('tweets') // 'tweets' | 'replies' | 'likes'
  const [tweets, setTweets] = useState(null)
  const [following, setFollowing] = useState(false)
  const [editing, setEditing] = useState(false)
  const [notFound, setNotFound] = useState(false)
  const websiteUrl = normalizeExternalUrl(profile?.website)

  const isOwnProfile = user && (profile?.id === user.id || authProfile?.username === username)

  const loadProfile = useCallback(async () => {
    try {
      const data = await fetchProfile(username)
      setProfile(data)
      if (user && data.id !== user.id) {
        isFollowing(user.id, data.id).then(setFollowing)
      }
    } catch {
      setNotFound(true)
    }
  }, [username, user])

  const loadTweets = useCallback(async () => {
    if (!profile) return
    try {
      const items = await fetchProfileTweets(profile.id, tab, user?.id)
      setTweets(items)
    } catch {
      setTweets([])
    }
  }, [profile, tab, user?.id])

  useEffect(() => {
    setProfile(null)
    setNotFound(false)
    loadProfile()
  }, [loadProfile])

  useEffect(() => {
    setTweets(null)
    loadTweets()
  }, [loadTweets])

  if (notFound) {
    return (
      <div>
        <PageHeader title="Profile" back />
        <EmptyState title="This account doesn't exist" text="Try searching for another." />
      </div>
    )
  }

  if (!profile) {
    return (
      <div>
        <PageHeader title="Profile" back />
        <Spinner />
      </div>
    )
  }

  return (
    <div>
      <PageHeader title={profile.display_name} subtitle={`${profile.follower_count || 0} Followers`} back />
      
      <div className="profile-cover" style={profile.cover_url ? { backgroundImage: `url(${profile.cover_url})` } : undefined} />
      
      <div className="profile-info">
        <div className="profile-avatar-row">
          <div className="profile-avatar">
            <Avatar profile={profile} size={120} />
          </div>
          <div>
            {isOwnProfile ? (
              <button className="btn btn-outline" onClick={() => setEditing(true)}>
                Edit profile
              </button>
            ) : (
              <FollowButton targetId={profile.id} initialFollowing={following} onChange={setFollowing} />
            )}
          </div>
        </div>

        <div className="profile-details">
          <div className="profile-names">
            <h1>{profile.display_name}</h1>
            <div className="muted">@{profile.username}</div>
          </div>

          {profile.bio && <div className="profile-bio">{profile.bio}</div>}

          <div className="profile-meta-row">
            {profile.location && (
              <div className="profile-meta-item">
                <Icon name="location" size={16} />
                <span>{profile.location}</span>
              </div>
            )}
            {websiteUrl && (
              <div className="profile-meta-item">
                <Icon name="link" size={16} />
                <a href={websiteUrl} target="_blank" rel="noreferrer" className="link-blue">
                  {websiteUrl.replace(/^https?:\/\//, '')}
                </a>
              </div>
            )}
            <div className="profile-meta-item">
              <Icon name="calendar" size={16} />
              <span>{joinDate(profile.created_at || Date.now())}</span>
            </div>
          </div>

          <div className="profile-stats">
            <span><strong>{profile.following_count || 0}</strong> <span className="muted">Following</span></span>
            <span><strong>{profile.follower_count || 0}</strong> <span className="muted">Followers</span></span>
          </div>
        </div>
      </div>

      <div className="tabs">
        <button className={`tab ${tab === 'tweets' ? 'active' : ''}`} onClick={() => setTab('tweets')}>
          <span>Tweets</span>
        </button>
        <button className={`tab ${tab === 'replies' ? 'active' : ''}`} onClick={() => setTab('replies')}>
          <span>Replies</span>
        </button>
        <button className={`tab ${tab === 'likes' ? 'active' : ''}`} onClick={() => setTab('likes')}>
          <span>Likes</span>
        </button>
      </div>

      {tweets === null ? (
        <Spinner />
      ) : tweets.length === 0 ? (
        <EmptyState title="No Tweets yet" text={`@${profile.username} has not posted any ${tab} yet.`} />
      ) : (
        tweets.map((item, i) => (
          <Tweet key={item.tweet.id + '-' + i} item={item} onDeleted={loadTweets} />
        ))
      )}

      {editing && (
        <EditProfileModal
          profile={profile}
          onClose={() => setEditing(false)}
          onSaved={loadProfile}
        />
      )}
    </div>
  )
}
