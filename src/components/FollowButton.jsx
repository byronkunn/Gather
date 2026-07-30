import { useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { setFollow } from '../lib/api'

export default function FollowButton({ targetId, initialFollowing, onChange }) {
  const { user } = useAuth()
  const [following, setFollowing] = useState(initialFollowing)
  const [hover, setHover] = useState(false)

  if (!user || user.id === targetId) return null

  const toggle = async (e) => {
    e.stopPropagation()
    const on = !following
    setFollowing(on)
    try {
      await setFollow(user.id, targetId, on)
      onChange?.(on)
    } catch {
      setFollowing(!on)
    }
  }

  return (
    <button
      className={`btn ${following ? (hover ? 'btn-danger-outline' : 'btn-outline') : 'btn-dark'}`}
      onClick={toggle}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
    >
      {following ? (hover ? 'Unfollow' : 'Following') : 'Follow'}
    </button>
  )
}
