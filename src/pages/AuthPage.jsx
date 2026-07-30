import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import Icon from '../components/Icons'

export default function AuthPage() {
  const { signIn, signUp } = useAuth()
  const navigate = useNavigate()
  const [mode, setMode] = useState('signin') // 'signin' | 'signup'
  const [form, setForm] = useState({ email: '', password: '', username: '', displayName: '' })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [notice, setNotice] = useState(null)

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  const submit = async (e) => {
    e.preventDefault()
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      if (mode === 'signup') {
        if (!/^\w{3,20}$/.test(form.username)) {
          throw new Error('Username must be 3–20 letters, numbers, or underscores.')
        }
        const data = await signUp(form.email, form.password, form.username.toLowerCase(), form.displayName || form.username)
        if (data?.session) {
          navigate('/home', { replace: true })
        } else {
          setNotice('Account created! Check your inbox to confirm your email, then sign in.')
          setMode('signin')
        }
      } else {
        await signIn(form.email, form.password)
        navigate('/home', { replace: true })
      }
    } catch (err) {
      setError(err.message || 'Something went wrong')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-hero">
        <Icon name="bird" size={280} className="auth-hero-bird" />
      </div>
      <div className="auth-panel">
        <Icon name="bird" size={44} className="blue" />
        <h1>Happening now</h1>
        <h2>{mode === 'signup' ? 'Join Twitter today' : 'Sign in to Twitter'}</h2>
        <form onSubmit={submit} className="auth-form">
          {mode === 'signup' && (
            <>
              <input
                placeholder="Username"
                value={form.username}
                onChange={set('username')}
                autoComplete="username"
                required
              />
              <input
                placeholder="Name"
                value={form.displayName}
                onChange={set('displayName')}
                autoComplete="name"
              />
            </>
          )}
          <input
            type="email"
            placeholder="Email"
            value={form.email}
            onChange={set('email')}
            autoComplete="email"
            required
          />
          <input
            type="password"
            placeholder="Password"
            value={form.password}
            onChange={set('password')}
            autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
            minLength={6}
            required
          />
          {error && <div className="auth-error">{error}</div>}
          {notice && <div className="auth-notice">{notice}</div>}
          <button className="btn btn-primary btn-block" disabled={busy}>
            {busy ? '…' : mode === 'signup' ? 'Create account' : 'Sign in'}
          </button>
        </form>
        <button
          className="auth-switch link-blue"
          onClick={() => {
            setMode(mode === 'signup' ? 'signin' : 'signup')
            setError(null)
          }}
        >
          {mode === 'signup' ? 'Already have an account? Sign in' : "Don't have an account? Sign up"}
        </button>
      </div>
    </div>
  )
}
