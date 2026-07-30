import { useRef, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { createTweet, saveDraft } from '../lib/api'
import Avatar from './Avatar'
import Icon from './Icons'

const MAX = 280

export default function TweetComposer({ replyTo = null, onPosted, autoFocus = false, placeholder }) {
  const { user, profile } = useAuth()
  const [text, setText] = useState('')
  const [file, setFile] = useState(null)
  const [preview, setPreview] = useState(null)
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [replyAudience, setReplyAudience] = useState('everyone')
  const [sensitive, setSensitive] = useState(false)
  const [pollEnabled, setPollEnabled] = useState(false)
  const [pollOptions, setPollOptions] = useState(['', ''])
  const [pollDays, setPollDays] = useState(1)
  const [draftMessage, setDraftMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const fileRef = useRef()
  const taRef = useRef()

  const remaining = MAX - text.length
  const validPollOptions = pollOptions.map((option) => option.trim()).filter(Boolean)
  const hasValidPoll = !pollEnabled || validPollOptions.length >= 2
  const hasContent = text.trim().length > 0 || Boolean(file) || pollEnabled
  const canPost = hasContent && remaining >= 0 && hasValidPoll && !busy
  const canSaveDraft = hasContent && !busy

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

  const buildComposerOptions = () => ({
    replyAudience,
    sensitive,
    poll: pollEnabled ? {
      options: validPollOptions.slice(0, 4),
      expiresAt: new Date(Date.now() + pollDays * 86400000).toISOString(),
      multipleChoice: false,
    } : null,
  })

  const resetComposer = () => {
    setText('')
    clearFile()
    setReplyAudience('everyone')
    setSensitive(false)
    setPollEnabled(false)
    setPollOptions(['', ''])
    setPollDays(1)
    setDraftMessage('')
    setShowAdvanced(false)
  }

  const post = async () => {
    if (!canPost) return
    setBusy(true)
    setError(null)
    setDraftMessage('')
    try {
      const tweet = await createTweet(user.id, text.trim(), file, replyTo?.id ?? null, buildComposerOptions())
      resetComposer()
      onPosted?.(tweet)
    } catch (err) {
      setError(err.message || 'Something went wrong')
    } finally {
      setBusy(false)
    }
  }

  const saveCurrentDraft = async () => {
    if (!canSaveDraft) return
    setBusy(true)
    setError(null)
    try {
      await saveDraft(user.id, text.trim(), file, {
        ...buildComposerOptions(),
        replyTo: replyTo?.id ?? null,
      })
      resetComposer()
      setDraftMessage('Draft saved')
    } catch (err) {
      setError(err.message || 'Could not save draft')
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
            setDraftMessage('')
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
        <div className="composer-secondary-bar">
          <button className="btn btn-outline btn-inline" onClick={() => setShowAdvanced((open) => !open)}>
            {showAdvanced ? 'Hide options' : 'More options'}
          </button>
          {draftMessage && <div className="composer-success">{draftMessage}</div>}
        </div>
        {showAdvanced && (
          <div className="composer-advanced">
            <label className="field field-compact">
              <span>Who can reply</span>
              <select value={replyAudience} onChange={(e) => setReplyAudience(e.target.value)}>
                <option value="everyone">Everyone</option>
                <option value="following">Accounts you follow</option>
                <option value="mentioned">Only mentioned accounts</option>
              </select>
            </label>
            <label className="composer-check">
              <input type="checkbox" checked={sensitive} onChange={(e) => setSensitive(e.target.checked)} />
              <span>Mark media as sensitive</span>
            </label>
            <label className="composer-check">
              <input type="checkbox" checked={pollEnabled} onChange={(e) => setPollEnabled(e.target.checked)} />
              <span>Add a poll</span>
            </label>
            {pollEnabled && (
              <div className="composer-poll">
                <input
                  className="composer-poll-input"
                  value={pollOptions[0]}
                  maxLength={25}
                  placeholder="Choice 1"
                  onChange={(e) => setPollOptions((current) => [e.target.value, current[1] || ''])}
                />
                <input
                  className="composer-poll-input"
                  value={pollOptions[1]}
                  maxLength={25}
                  placeholder="Choice 2"
                  onChange={(e) => setPollOptions((current) => [current[0] || '', e.target.value])}
                />
                <label className="field field-compact composer-poll-expiry">
                  <span>Poll length</span>
                  <select value={pollDays} onChange={(e) => setPollDays(Number(e.target.value))}>
                    <option value={1}>1 day</option>
                    <option value={3}>3 days</option>
                    <option value={7}>7 days</option>
                  </select>
                </label>
              </div>
            )}
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
            <button className="btn btn-outline btn-inline" disabled={!canSaveDraft} onClick={saveCurrentDraft}>
              Save draft
            </button>
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
