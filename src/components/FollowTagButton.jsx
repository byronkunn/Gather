import { useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { setTagFollow } from '../lib/api'

export default function FollowTagButton({ tag, initialFollowing = false, onChange, compact = false }) {
  const { user } = useAuth()
  const [following, setFollowing] = useState(initialFollowing)
  const [busy, setBusy] = useState(false)

  const toggle = async () => {
    if (!user || busy) return
    const next = !following
    setFollowing(next)
    setBusy(true)
    try {
      await setTagFollow(user.id, tag, next)
      onChange?.(next)
    } catch {
      setFollowing(!next)
    } finally {
      setBusy(false)
    }
  }

  return (
    <button className={`btn ${following ? 'btn-outline' : 'btn-primary'} ${compact ? 'btn-tag-compact' : ''}`} onClick={toggle} disabled={busy}>
      {busy ? '...' : following ? 'Following' : 'Follow'}
    </button>
  )
}