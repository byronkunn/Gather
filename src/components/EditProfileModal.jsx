import { useEffect, useRef, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { updateProfile, uploadImage } from '../lib/api'
import Avatar from './Avatar'
import Icon from './Icons'
import Modal from './Modal'

export default function EditProfileModal({ profile, onClose, onSaved }) {
  const { user, refreshProfile } = useAuth()
  const [form, setForm] = useState({
    display_name: profile.display_name || '',
    bio: profile.bio || '',
    location: profile.location || '',
    website: profile.website || '',
  })
  const [avatarFile, setAvatarFile] = useState(null)
  const [avatarPreview, setAvatarPreview] = useState(null)
  const [coverFile, setCoverFile] = useState(null)
  const [coverPreview, setCoverPreview] = useState(null)
  const [busy, setBusy] = useState(false)
  const avatarRef = useRef()
  const coverRef = useRef()

  useEffect(() => () => {
    if (avatarPreview) URL.revokeObjectURL(avatarPreview)
  }, [avatarPreview])

  useEffect(() => () => {
    if (coverPreview) URL.revokeObjectURL(coverPreview)
  }, [coverPreview])

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  const save = async () => {
    setBusy(true)
    try {
      const fields = { ...form }
      if (avatarFile) fields.avatar_url = await uploadImage(user.id, avatarFile)
      if (coverFile) fields.cover_url = await uploadImage(user.id, coverFile)
      await updateProfile(user.id, fields)
      await refreshProfile()
      onSaved?.()
      onClose()
    } catch (err) {
      alert(err.message || 'Failed to save')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal onClose={onClose}>
      <div className="edit-profile">
        <div className="modal-header">
          <h2>Edit profile</h2>
          <button className="btn btn-dark" disabled={busy} onClick={save}>Save</button>
        </div>
        <div className="edit-cover" style={coverPreview || profile.cover_url ? { backgroundImage: `url(${coverPreview || profile.cover_url})` } : undefined}>
          <button className="icon-btn overlay-btn" onClick={() => coverRef.current?.click()} aria-label="Change cover">
            <Icon name="image" size={20} />
          </button>
          <input ref={coverRef} type="file" accept="image/*" hidden onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) { setCoverFile(f); setCoverPreview(URL.createObjectURL(f)) }
          }} />
        </div>
        <div className="edit-avatar">
          {avatarPreview
            ? <img src={avatarPreview} alt="" className="avatar" style={{ width: 90, height: 90 }} />
            : <Avatar profile={profile} size={90} />}
          <button className="icon-btn overlay-btn" onClick={() => avatarRef.current?.click()} aria-label="Change avatar">
            <Icon name="image" size={20} />
          </button>
          <input ref={avatarRef} type="file" accept="image/*" hidden onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) { setAvatarFile(f); setAvatarPreview(URL.createObjectURL(f)) }
          }} />
        </div>
        <div className="edit-fields">
          <label className="field">
            <span>Name</span>
            <input value={form.display_name} maxLength={50} onChange={set('display_name')} />
          </label>
          <label className="field">
            <span>Bio</span>
            <textarea value={form.bio} maxLength={160} rows={3} onChange={set('bio')} />
          </label>
          <label className="field">
            <span>Location</span>
            <input value={form.location} maxLength={30} onChange={set('location')} />
          </label>
          <label className="field">
            <span>Website</span>
            <input value={form.website} maxLength={100} onChange={set('website')} />
          </label>
        </div>
      </div>
    </Modal>
  )
}
