import { useNavigate } from 'react-router-dom'
import Icon from './Icons'
import BrandMark from './BrandMark'

export function Spinner() {
  return (
    <div className="spinner-wrap">
      <div className="spinner" />
    </div>
  )
}

export function PageHeader({ title, subtitle, back = false, children }) {
  const navigate = useNavigate()
  return (
    <div className="page-header">
      <div className="page-header-row">
        {back && (
          <button className="icon-btn" onClick={() => navigate(-1)} aria-label="Back">
            <Icon name="back" size={20} />
          </button>
        )}
        <div className="page-header-titles">
          <h1>{title}</h1>
          {subtitle && <div className="muted small">{subtitle}</div>}
        </div>
      </div>
      {children}
    </div>
  )
}

export function EmptyState({ title, text }) {
  return (
    <div className="empty-state">
      <h2>{title}</h2>
      {text && <p className="muted">{text}</p>}
    </div>
  )
}

export function SetupScreen() {
  return (
    <div className="setup-screen">
      <BrandMark size={48} />
      <h1>Almost there</h1>
      <p>
        Supabase isn't configured yet. Copy <code>.env.example</code> to <code>.env</code>,
        add your project URL and anon key, run <code>supabase/schema.sql</code> in the
        Supabase SQL Editor, then restart the dev server.
      </p>
    </div>
  )
}
