import { NavLink } from 'react-router-dom'
import { useUi } from '../context/UiContext'
import Icon from './Icons'

export default function MobileNav() {
  const { unread, openCompose } = useUi()

  const items = [
    { to: '/home', icon: 'homeOutline', activeIcon: 'home', label: 'Home' },
    { to: '/explore', icon: 'search', activeIcon: 'searchBold', label: 'Explore' },
    { to: '/notifications', icon: 'bell', activeIcon: 'bellFilled', label: 'Notifications', badge: unread.notifications },
    { to: '/messages', icon: 'mail', activeIcon: 'mailFilled', label: 'Messages', badge: unread.messages },
  ]

  return (
    <>
      <button className="fab" onClick={() => openCompose()} aria-label="Tweet">
        <Icon name="feather" size={24} />
      </button>
      <nav className="mobile-nav">
        {items.map((item) => (
          <NavLink key={item.label} to={item.to} className="mobile-nav-item" aria-label={item.label}>
            {({ isActive }) => (
              <span className="nav-icon">
                <Icon name={isActive ? item.activeIcon : item.icon} size={26} />
                {item.badge > 0 && <span className="nav-badge">{item.badge > 99 ? '99+' : item.badge}</span>}
              </span>
            )}
          </NavLink>
        ))}
      </nav>
    </>
  )
}
