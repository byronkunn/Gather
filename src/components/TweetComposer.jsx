import { useRef, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { createTweet } from '../lib/api'
import Avatar from './Avatar'
import Icon from './Icons'

const MAX = 280

export default function TweetComposer({ replyTo = null, onPosted, autoFocus = false, placeholder }) {
  const { user, profile } = useAuth()
  const [text, setText] = useState('')
  const [file, setFile] = useState(null)
  const [preview, setPreview] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const fileRef = useRef()
  const taRef = useRef()

  const remaining = MAX - text.length
  const canPost = text.trim().length > 0 && remaining >= 0 && !busy

  const pickFile = (e) => {
    const f = e.target.files?.[0]
    if (!f) return
    setFile(f)
    setPreview(URL.createObjectURL(f))
  }

  const clearFile = () => {
    setFile(null)
    if (preview) URL.revokeObjectURL(preview)
    setPreview(null)
    if (fileRef.current) fileRef.current.value = ''
  }

  const post = async () => {
    if (!canPost) return
    setBusy(true)
    setError(null)
    try {
      const tweet = await createTweet(user.id, text.trim(), file, replyTo?.id ?? null)
      setText('')
      clearFile()
      onPosted?.(tweet)
    } catch (err) {
      setError(err.message || 'Something went wrong')
    } finally {
      setBusy(false)
    }
  }

  const autogrow = (el) => {
    el.style.height = 'auto'
    el.style.height = el.scrollHeight + 'px'
  }

  // circular progress for the char counter
  const pct = Math.min(text.length / MAX, 1)
  const warn = remaining <= 20

  return (
    <div className="composer">
      <Avatar profile={profile} size={40} />
      <div className="composer-main">
        {replyTo && (
          <div className="composer-replying">
            Replying to <span className="link-blue">@{replyTo.author?.username}</span>
          </div>
        )}
        <textarea
          ref={taRef}
          className="composer-input"
          placeholder={placeholder || (replyTo ? 'Tweet your reply' : "What's happening?")}
          value={text}
          rows={1}
          autoFocus={autoFocus}
          maxLength={MAX + 50}
          onChange={(e) => {
            setText(e.target.value)
            autogrow(e.target)
          }}
          onKeyDown={(e) => {
            if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') post()
          }}
        />
        {preview && (
          <div className="composer-preview">
            <img src={preview} alt="attachment" />
            <button className="icon-btn preview-remove" onClick={clearFile} aria-label="Remove image">
              <Icon name="close" size={18} />
            </button>
          </div>
        )}
        {error && <div className="composer-error">{error}</div>}
        <div className="composer-bar">
          <div className="composer-tools">
            <button className="icon-btn blue" onClick={() => fileRef.current?.click()} aria-label="Add image">
              <Icon name="image" size={20} />
            </button>
            <input ref={fileRef} type="file" accept="image/*" hidden onChange={pickFile} />
          </div>
          <div className="composer-actions">
            {text.length > 0 && (
              <div className={`char-ring ${warn ? 'warn' : ''} ${remaining < 0 ? 'over' : ''}`}>
                {warn ? (
                  <span>{remaining}</span>
                ) : (
                  <svg width="24" height="24" viewBox="0 0 24 24">
                    <circle cx="12" cy="12" r="10" fill="none" strokeWidth="2" className="ring-track" />
                    <circle
                      cx="12" cy="12" r="10" fill="none" strokeWidth="2"
                      className="ring-fill"
                      strokeDasharray={`${pct * 62.8} 62.8`}
                      transform="rotate(-90 12 12)"
                    />
                  </svg>
                )}
              </div>
            )}
            <button className="btn btn-primary btn-tweet" disabled={!canPost} onClick={post}>
              {replyTo ? 'Reply' : 'Tweet'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
