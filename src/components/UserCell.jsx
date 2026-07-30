import { useNavigate } from 'react-router-dom'
import Avatar from './Avatar'
import FollowButton from './FollowButton'

export default function UserCell({ profile, following = false, showFollow = true }) {
  const navigate = useNavigate()
  return (
    <div className="user-cell" onClick={() => navigate(`/${profile.username}`)}>
      <Avatar profile={profile} size={40} />
      <div className="user-cell-names">
        <div className="bold ellipsis">{profile.display_name}</div>
        <div className="muted ellipsis">@{profile.username}</div>
        {profile.bio && <div className="user-cell-bio">{profile.bio}</div>}
      </div>
      {showFollow && <FollowButton targetId={profile.id} initialFollowing={following} />}
    </div>
  )
}
