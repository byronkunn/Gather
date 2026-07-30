import { useEffect, useRef, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { fetchConversations, fetchThread, sendMessage, markThreadRead, searchUsers } from '../lib/api'
import { Spinner, EmptyState } from '../components/Shared'
import Avatar from '../components/Avatar'
import Icon from '../components/Icons'
import { timeAgo } from '../lib/format'

export default function MessagesPage() {
  const { user } = useAuth()
  const [conversations, setConversations] = useState([])
  const [activeUser, setActiveUser] = useState(null)
  const [thread, setThread] = useState([])
  const [text, setText] = useState('')
  const [loading, setLoading] = useState(true)
  const [conversationError, setConversationError] = useState(false)
  const [threadError, setThreadError] = useState(false)
  const [query, setQuery] = useState('')
  const [people, setPeople] = useState([])
  const [searching, setSearching] = useState(false)
  const [filter, setFilter] = useState('all')
  const [composing, setComposing] = useState(false)
  const searchRef = useRef(null)

  useEffect(() => {
    if (!user) return
    setConversationError(false)
    fetchConversations(user.id)
      .then(convos => {
        setConversations(convos)
        if (convos.length > 0 && !activeUser) {
          setActiveUser(convos[0].other)
        }
      })
      .catch(() => setConversationError(true))
      .finally(() => setLoading(false))
  }, [user])

  useEffect(() => {
    if (!user || !activeUser) return
    setThread([])
    setThreadError(false)
    fetchThread(user.id, activeUser.id)
      .then(setThread)
      .catch(() => setThreadError(true))
    markThreadRead(user.id, activeUser.id).catch(() => setThreadError(true))
  }, [user, activeUser])

  useEffect(() => {
    const term = query.trim()
    if (term.length < 2) {
      setPeople([])
      setSearching(false)
      return
    }

    let current = true
    setSearching(true)
    const timeout = window.setTimeout(() => {
      searchUsers(term)
        .then(results => {
          if (current) setPeople(results.filter(person => person.id !== user?.id))
        })
        .catch(() => {
          if (current) setPeople([])
        })
        .finally(() => {
          if (current) setSearching(false)
        })
    }, 250)

    return () => {
      current = false
      window.clearTimeout(timeout)
    }
  }, [query, user?.id])

  const selectPerson = (person) => {
    setActiveUser(person)
    setConversations(current => current.map(conversation => (
      conversation.other.id === person.id ? { ...conversation, unread: 0 } : conversation
    )))
    setQuery('')
    setPeople([])
    setComposing(false)
  }

  const startMessage = () => {
    setComposing(true)
    setQuery('')
    window.requestAnimationFrame(() => searchRef.current?.focus())
  }

  const normalizedQuery = query.trim().toLowerCase()
  const visibleConversations = conversations.filter(conversation => {
    if (filter === 'unread' && !conversation.unread) return false
    if (filter === 'groups' || filter === 'requests' || filter === 'settings') return false
    if (!normalizedQuery) return true
    return conversation.other.display_name?.toLowerCase().includes(normalizedQuery)
      || conversation.other.username?.toLowerCase().includes(normalizedQuery)
  })
  const showingPeople = composing || normalizedQuery.length >= 2

  const handleSend = async (e) => {
    e.preventDefault()
    if (!text.trim() || !activeUser || !user) return
    const content = text.trim()
    setText('')
    setThreadError(false)
    try {
      const newMsg = await sendMessage(user.id, activeUser.id, content)
      setThread(t => [...t, newMsg])
    } catch {
      setText(content)
      setThreadError(true)
    }
  }

  return (
    <div className={`messages-container ${activeUser ? 'has-active-thread' : ''}`}>
      <div className="conversations-list">
        <div className="messages-sidebar-header">
          <div className="messages-title-row">
            <h1>Messages</h1>
          </div>
          <div className="message-toolbar">
            <label className="message-search">
              <Icon name="search" size={18} />
              <input
                ref={searchRef}
                type="search"
                placeholder={composing ? 'Search people to message' : 'Search people'}
                value={query}
                onChange={event => setQuery(event.target.value)}
              />
            </label>
            <select value={filter} onChange={event => setFilter(event.target.value)} aria-label="Filter messages">
              <option value="all">All</option>
              <option value="unread">Unread</option>
              <option value="direct">Direct</option>
              <option value="groups">Groups</option>
              <option value="requests">Requests</option>
              <option value="settings">Settings</option>
            </select>
            <button className="icon-btn new-message-btn" onClick={startMessage} aria-label="New message" title="New message">
              <Icon name="message" size={20} />
            </button>
          </div>
        </div>
        {loading ? (
          <Spinner />
        ) : conversationError ? (
          <EmptyState title="Couldn’t load messages" text="Please try again in a moment." />
        ) : showingPeople ? (
          <div className="people-results">
            {searching ? (
              <Spinner />
            ) : normalizedQuery.length < 2 ? (
              <EmptyState title="New message" text="Search for someone to start a conversation." />
            ) : people.length === 0 ? (
              <EmptyState title="No people found" text="Try another name or username." />
            ) : people.map(person => (
              <button key={person.id} className="person-result" onClick={() => selectPerson(person)}>
                <Avatar profile={person} size={42} />
                <span>
                  <span className="bold ellipsis">{person.display_name}</span>
                  <span className="muted small ellipsis">@{person.username}</span>
                </span>
              </button>
            ))}
          </div>
        ) : conversations.length === 0 ? (
          <EmptyState title="Welcome to your inbox!" text="Drop a line, share Tweets and more with private conversations between you and others on Twitter." />
        ) : visibleConversations.length === 0 ? (
          <EmptyState title="No messages here" text="There aren’t any conversations in this view." />
        ) : (
          visibleConversations.map(c => (
            <button
              key={c.other.id}
              className={`conversation-item ${activeUser?.id === c.other.id ? 'active' : ''}`}
              onClick={() => selectPerson(c.other)}
            >
              <Avatar profile={c.other} size={40} />
              <span className="conversation-copy">
                <span className="conversation-line">
                  <span className="bold ellipsis">{c.other.display_name}</span>
                  <span className="muted small">{timeAgo(c.lastMessage.created_at)}</span>
                </span>
                <span className="conversation-preview">
                  <span className={`small ellipsis ${c.unread ? 'bold' : 'muted'}`}>{c.lastMessage.content}</span>
                  {c.unread > 0 && <span className="conversation-unread">{c.unread > 9 ? '9+' : c.unread}</span>}
                </span>
              </span>
            </button>
          ))
        )}
      </div>

      <div className="chat-view">
        {activeUser ? (
          <>
            <div className="chat-header">
              <button className="icon-btn chat-back" onClick={() => setActiveUser(null)} aria-label="Back to messages">
                <Icon name="back" size={20} />
              </button>
              <Avatar profile={activeUser} size={36} />
              <div>
                <div className="bold">{activeUser.display_name}</div>
                <div className="muted small">@{activeUser.username}</div>
              </div>
            </div>
            <div className="chat-messages">
              {threadError ? (
                <EmptyState title="Something went wrong" text="Your messages couldn’t be updated. Please try again." />
              ) : thread.map(m => (
                <div
                  key={m.id}
                  className={`message-bubble ${m.sender_id === user?.id ? 'mine' : 'other'}`}
                >
                  {m.content}
                </div>
              ))}
            </div>
            <form className="chat-input-bar" onSubmit={handleSend}>
              <input
                placeholder="Start a new message"
                value={text}
                onChange={e => setText(e.target.value)}
              />
              <button className="icon-btn blue" disabled={!text.trim()} aria-label="Send">
                <Icon name="share" size={20} />
              </button>
            </form>
          </>
        ) : (
          <EmptyState title="Select a message" text="Choose from your existing conversations, or start a new one." />
        )}
      </div>
    </div>
  )
}
