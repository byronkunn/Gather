import { useEffect, useState, useCallback } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { addMutedWord, fetchFollowingTags, fetchMutedWords, fetchProfile, fetchProfileTweets, fetchTweet, isFollowing, removeMutedWord } from '../lib/api'
import Tweet from '../components/Tweet'
import Avatar from '../components/Avatar'
import FollowButton from '../components/FollowButton'
import FollowTagButton from '../components/FollowTagButton'
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
  const [followingTags, setFollowingTags] = useState([])
  const [pinnedTweet, setPinnedTweet] = useState(null)
  const [mutedWords, setMutedWords] = useState([])
  const [mutedWordInput, setMutedWordInput] = useState('')
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

  const loadFollowingTags = useCallback(async () => {
    if (!user) return
    try {
      setFollowingTags(await fetchFollowingTags(user.id))
    } catch {
      setFollowingTags([])
    }
  }, [user])

  const loadPinnedTweet = useCallback(async () => {
    if (!profile?.pinned_tweet_id || !user?.id) {
      setPinnedTweet(null)
      return
    }
    try {
      setPinnedTweet(await fetchTweet(profile.pinned_tweet_id, user.id))
    } catch {
      setPinnedTweet(null)
    }
  }, [profile?.pinned_tweet_id, user?.id])

  const loadMutedWords = useCallback(async () => {
    if (!user) return
    try {
      setMutedWords(await fetchMutedWords(user.id))
    } catch {
      setMutedWords([])
    }
  }, [user])

  useEffect(() => {
    setProfile(null)
    setNotFound(false)
    loadProfile()
  }, [loadProfile])

  useEffect(() => {
    setTweets(null)
    loadTweets()
  }, [loadTweets])

  useEffect(() => {
    if (isOwnProfile) {
      loadFollowingTags()
      loadMutedWords()
    }
  }, [isOwnProfile, loadFollowingTags, loadMutedWords])

  useEffect(() => {
    loadPinnedTweet()
  }, [loadPinnedTweet])

  const addMutedPhrase = async () => {
    const value = mutedWordInput.trim()
    if (!value) return
    const created = await addMutedWord(user.id, value)
    setMutedWords((current) => [created, ...current.filter((item) => (item.id || item.phrase) !== (created.id || created.phrase))])
    setMutedWordInput('')
  }

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

          {pinnedTweet && (
            <div className="profile-pinned-card">
              <div className="section-label">Pinned post</div>
              <Tweet item={pinnedTweet} onDeleted={() => { loadPinnedTweet(); loadTweets() }} />
            </div>
          )}

          {isOwnProfile && (
            <div className="profile-tags-card">
              <div className="section-label">Following Tags</div>
              {followingTags.length === 0 ? (
                <div className="muted">Follow tags like #react to see them here.</div>
              ) : (
                <div className="profile-tags-list">
                  {followingTags.map((tag) => (
                    <div key={tag.normalized_name} className="profile-tag-row">
                      <Link to={`/tags/${tag.normalized_name}`} className="tag-chip-link">#{tag.normalized_name}</Link>
                      <div className="profile-tag-actions">
                        <span className="muted small">{tag.post_count || 0} posts</span>
                        <FollowTagButton tag={tag.normalized_name} initialFollowing onChange={(next) => {
                          if (!next) setFollowingTags((current) => current.filter((item) => item.normalized_name !== tag.normalized_name))
                        }} compact />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {isOwnProfile && (
            <div className="profile-safety-card">
              <div className="section-label">Safety and filters</div>
              <div className="profile-muted-input-row">
                <input
                  value={mutedWordInput}
                  onChange={(e) => setMutedWordInput(e.target.value)}
                  placeholder="Mute a word or phrase"
                />
                <button className="btn btn-outline btn-inline" onClick={addMutedPhrase}>Add</button>
              </div>
              {mutedWords.length === 0 ? (
                <div className="muted">Muted words will be filtered from your home feed, search, and tag timelines.</div>
              ) : (
                <div className="muted-word-list">
                  {mutedWords.map((item) => (
                    <button
                      key={item.id || item.phrase}
                      className="muted-word-chip"
                      onClick={async () => {
                        await removeMutedWord(user.id, item.id || item.phrase)
                        setMutedWords((current) => current.filter((word) => (word.id || word.phrase) !== (item.id || item.phrase)))
                      }}
                    >
                      {item.phrase} ×
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      <div className="tabs">
        <button className={`tab ${tab === 'tweets' ? 'active' : ''}`} onClick={() => setTab('tweets')}>
          <span>Tweets</span>
        </button>
        <button className={`tab ${tab === 'media' ? 'active' : ''}`} onClick={() => setTab('media')}>
          <span>Media</span>
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
