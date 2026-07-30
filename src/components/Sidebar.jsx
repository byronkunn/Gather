import { useState } from 'react'
import { NavLink, Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { useTheme } from '../context/ThemeContext'
import { useUi } from '../context/UiContext'
import Avatar from './Avatar'
import Icon from './Icons'

const THEME_LABELS = { light: 'Default', dim: 'Dim', dark: 'Lights out' }

export default function Sidebar({ compact = false }) {
  const { profile, signOut } = useAuth()
  const { theme, setTheme, themes } = useTheme()
  const { openCompose, unread } = useUi()
  const [menuOpen, setMenuOpen] = useState(false)
  const [signingOut, setSigningOut] = useState(false)
  const profilePath = profile?.username ? `/${profile.username}` : '/home'

  const handleSignOut = async () => {
    setSigningOut(true)
    try {
      await signOut()
      setMenuOpen(false)
    } catch {
      alert('Could not sign out right now. Please try again.')
    } finally {
      setSigningOut(false)
    }
  }

  const items = [
    { to: '/home', label: 'Home', icon: 'homeOutline', activeIcon: 'home' },
    { to: '/explore', label: 'Explore', icon: 'search', activeIcon: 'searchBold' },
    { to: '/notifications', label: 'Notifications', icon: 'bell', activeIcon: 'bellFilled', badge: unread.notifications },
    { to: '/messages', label: 'Messages', icon: 'mail', activeIcon: 'mailFilled', badge: unread.messages },
    { to: '/bookmarks', label: 'Bookmarks', icon: 'bookmark', activeIcon: 'bookmarkFilled' },
    { to: profilePath, label: 'Profile', icon: 'user', activeIcon: 'userFilled' },
  ]

  return (
    <header className={`sidebar ${compact ? 'sidebar-compact' : ''}`}>
      <div className="sidebar-inner">
        <Link to="/home" className="sidebar-logo" aria-label="Twitter">
          <Icon name="bird" size={28} />
        </Link>
        <nav className="sidebar-nav">
          {items.map((item) => (
            <NavLink key={item.label} to={item.to} className="nav-item">
              {({ isActive }) => (
                <>
                  <span className="nav-icon">
                    <Icon name={isActive ? item.activeIcon : item.icon} size={26} />
                    {item.badge > 0 && <span className="nav-badge">{item.badge > 99 ? '99+' : item.badge}</span>}
                  </span>
                  <span className={`nav-label ${isActive ? 'bold' : ''}`}>{item.label}</span>
                </>
              )}
            </NavLink>
          ))}
        </nav>
        <button className="btn btn-primary sidebar-tweet-btn" onClick={() => openCompose()}>
          <span className="sidebar-tweet-label">Tweet</span>
          <span className="sidebar-tweet-icon"><Icon name="feather" size={24} /></span>
        </button>
        <div className="sidebar-account-wrap">
          {menuOpen && (
            <div className="dropdown dropdown-up">
              <div className="dropdown-section-title">Theme</div>
              {themes.map((t) => (
                <button
                  key={t}
                  className={`dropdown-item ${theme === t ? 'selected' : ''}`}
                  onClick={() => setTheme(t)}
                >
                  {THEME_LABELS[t]} {theme === t && '✓'}
                </button>
              ))}
              <div className="dropdown-divider" />
              <button className="dropdown-item" onClick={handleSignOut} disabled={signingOut}>
                {signingOut ? 'Logging out…' : `Log out @${profile?.username || 'account'}`}
              </button>
            </div>
          )}
          <button className="sidebar-account" onClick={() => setMenuOpen((o) => !o)}>
            <Avatar profile={profile} size={40} />
            <div className="sidebar-account-names">
              <div className="bold ellipsis">{profile?.display_name}</div>
              <div className="muted ellipsis">@{profile?.username}</div>
            </div>
            <Icon name="dots" size={18} className="muted" />
          </button>
        </div>
      </div>
    </header>
  )
}
