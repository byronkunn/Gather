import { createContext, useContext, useCallback, useEffect, useState } from 'react'
import { useAuth } from './AuthContext'
import { fetchUnreadCounts, subscribeToMessages, subscribeToNotifications } from '../lib/api'

// App-wide UI state: compose modal + unread badge counts.
const UiContext = createContext(null)

export function UiProvider({ children }) {
  const { user } = useAuth()
  const [composeState, setComposeState] = useState(null) // null | { replyTo: tweet|null }
  const [unread, setUnread] = useState({ notifications: 0, messages: 0 })

  const refreshUnread = useCallback(async () => {
    if (!user) return
    try {
      setUnread(await fetchUnreadCounts(user.id))
    } catch { /* ignore */ }
  }, [user])

  useEffect(() => {
    if (!user) return
    refreshUnread()
    const offMsg = subscribeToMessages(user.id, refreshUnread)
    const offNotif = subscribeToNotifications(user.id, refreshUnread)
    return () => {
      offMsg()
      offNotif()
    }
  }, [user, refreshUnread])

  const openCompose = (replyTo = null) => setComposeState({ replyTo })
  const closeCompose = () => setComposeState(null)

  return (
    <UiContext.Provider value={{ composeState, openCompose, closeCompose, unread, refreshUnread }}>
      {children}
    </UiContext.Provider>
  )
}

export const useUi = () => useContext(UiContext)
