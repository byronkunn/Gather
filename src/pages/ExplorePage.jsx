import { useState, useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { searchTweets, searchUsers, fetchTrends, fetchWhoToFollow } from '../lib/api'
import Tweet from '../components/Tweet'
import UserCell from '../components/UserCell'
import { Spinner, EmptyState } from '../components/Shared'
import Icon from '../components/Icons'
import { compact } from '../lib/format'

export default function ExplorePage() {
  const { user } = useAuth()
  const [searchParams, setSearchParams] = useSearchParams()
  const queryParam = searchParams.get('q') || ''
  const [query, setQuery] = useState(queryParam)
  const [tab, setTab] = useState('top') // 'top' | 'latest' | 'people'
  const [tweets, setTweets] = useState([])
  const [users, setUsers] = useState([])
  const [trends, setTrends] = useState([])
  const [suggestions, setSuggestions] = useState([])
  const [loading, setLoading] = useState(false)
  const viewerId = user?.id || 'demo-user-id'

  useEffect(() => {
    setQuery(queryParam)
    if (!queryParam) {
      fetchTrends().then(setTrends).catch(() => {})
      fetchWhoToFollow(viewerId).then(setSuggestions).catch(() => {})
    } else {
      setLoading(true)
      Promise.all([
        searchTweets(queryParam, viewerId),
        searchUsers(queryParam)
      ]).then(([tData, uData]) => {
        setTweets(tData)
        setUsers(uData)
      }).catch(() => {
        setTweets([])
        setUsers([])
      }).finally(() => setLoading(false))
    }
  }, [queryParam, viewerId])

  const displayedTweets = [...tweets].sort((a, b) => {
    if (tab === 'latest') {
      return new Date(b.created_at) - new Date(a.created_at)
    }
    const scoreA = (a.like_count || 0) + ((a.retweet_count || 0) * 2) + (a.reply_count || 0)
    const scoreB = (b.like_count || 0) + ((b.retweet_count || 0) * 2) + (b.reply_count || 0)
    if (scoreA !== scoreB) return scoreB - scoreA
    return new Date(b.created_at) - new Date(a.created_at)
  })

  const handleSearchSubmit = (e) => {
    e.preventDefault()
    if (query.trim()) {
      setSearchParams({ q: query.trim() })
    } else {
      setSearchParams({})
    }
  }

  return (
    <div>
      <div className="page-header">
        <form className="search-box" style={{ padding: '12px 16px' }} onSubmit={handleSearchSubmit}>
          <Icon name="search" size={18} className="search-icon" />
          <input
            type="search"
            placeholder="Search Twitter"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </form>
        {queryParam && (
          <div className="tabs">
            <button className={`tab ${tab === 'top' ? 'active' : ''}`} onClick={() => setTab('top')}>
              <span>Top</span>
            </button>
            <button className={`tab ${tab === 'latest' ? 'active' : ''}`} onClick={() => setTab('latest')}>
              <span>Latest</span>
            </button>
            <button className={`tab ${tab === 'people' ? 'active' : ''}`} onClick={() => setTab('people')}>
              <span>People</span>
            </button>
          </div>
        )}
      </div>

      {queryParam ? (
        loading ? (
          <Spinner />
        ) : tab === 'people' ? (
          users.length === 0 ? (
            <EmptyState title="No results found" text={`No accounts matching "${queryParam}"`} />
          ) : (
            users.map(u => <UserCell key={u.id} profile={u} />)
          )
        ) : tweets.length === 0 ? (
          <EmptyState title="No results found" text={`No tweets matching "${queryParam}"`} />
        ) : (
          displayedTweets.map(t => <Tweet key={t.id} item={t} />)
        )
      ) : (
        <div style={{ padding: '16px' }}>
          <section className="panel-card" style={{ marginBottom: '24px' }}>
            <h2 className="panel-title">Trends for you</h2>
            {trends.map((t) => (
              <button
                key={t.tag}
                className="trend-item"
                onClick={() => setSearchParams({ q: '#' + t.tag })}
              >
                <div className="muted small">Trending in Tech</div>
                <div className="bold" style={{ fontSize: 16 }}>#{t.tag}</div>
                <div className="muted small">{compact(t.tweet_count)} Tweets</div>
              </button>
            ))}
          </section>

          <section className="panel-card">
            <h2 className="panel-title">Who to follow</h2>
            {suggestions.map((p) => (
              <UserCell key={p.id} profile={p} />
            ))}
          </section>
        </div>
      )}
    </div>
  )
}
