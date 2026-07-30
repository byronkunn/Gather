import { useEffect, useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { fetchTrends, fetchWhoToFollow } from '../lib/api'
import { compact } from '../lib/format'
import Icon from './Icons'
import UserCell from './UserCell'

export default function RightPanel() {
  const { user } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [query, setQuery] = useState('')
  const [trends, setTrends] = useState([])
  const [suggestions, setSuggestions] = useState([])

  useEffect(() => {
    fetchTrends().then(setTrends).catch(() => {})
    if (user) fetchWhoToFollow(user.id).then(setSuggestions).catch(() => {})
  }, [user])

  const onSearch = (e) => {
    e.preventDefault()
    if (query.trim()) navigate(`/explore?q=${encodeURIComponent(query.trim())}`)
  }

  const onExplore = location.pathname.startsWith('/explore')

  return (
    <aside className="right-panel">
      {!onExplore && (
        <form className="search-box" onSubmit={onSearch}>
          <Icon name="search" size={18} className="search-icon" />
          <input
            type="search"
            placeholder="Search Twitter"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </form>
      )}
      {trends.length > 0 && (
        <section className="panel-card">
          <h2 className="panel-title">Trends for you</h2>
          {trends.map((t) => (
            <button
              key={t.tag}
              className="trend-item"
              onClick={() => navigate(`/explore?q=${encodeURIComponent('#' + t.tag)}`)}
            >
              <div className="muted small">Trending</div>
              <div className="bold">#{t.tag}</div>
              <div className="muted small">{compact(t.tweet_count)} Tweets</div>
            </button>
          ))}
        </section>
      )}
      {suggestions.length > 0 && (
        <section className="panel-card">
          <h2 className="panel-title">Who to follow</h2>
          {suggestions.map((p) => (
            <UserCell key={p.id} profile={p} />
          ))}
        </section>
      )}
      <footer className="panel-footer muted small">
        Twitter clone · Built with React + Supabase
      </footer>
    </aside>
  )
}
