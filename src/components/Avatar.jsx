export default function Avatar({ profile, size = 40, className = '' }) {
  const style = { width: size, height: size }
  if (profile?.avatar_url) {
    return (
      <img
        src={profile.avatar_url}
        alt={profile.display_name || ''}
        className={`avatar ${className}`}
        style={style}
        loading="lazy"
      />
    )
  }
  const letter = (profile?.display_name || profile?.username || '?')[0]?.toUpperCase()
  // deterministic hue from username so each user gets a stable color
  const hue = [...(profile?.username || 'x')].reduce((a, c) => a + c.charCodeAt(0), 0) % 360
  return (
    <div
      className={`avatar avatar-fallback ${className}`}
      style={{ ...style, background: `hsl(${hue}, 55%, 45%)`, fontSize: size * 0.42 }}
    >
      {letter}
    </div>
  )
}
