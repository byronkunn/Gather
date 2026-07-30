import { createContext, useContext, useEffect, useState, useCallback } from 'react'
import { supabase, isConfigured } from '../lib/supabase'
import { fetchProfile } from '../lib/api'

const AuthContext = createContext(null)

const MOCK_USER = {
  id: 'demo-user-id',
  email: 'alex@example.com',
}

export function AuthProvider({ children }) {
  const [session, setSession] = useState(isConfigured ? null : { user: MOCK_USER })
  const [profile, setProfile] = useState(null)
  const [loading, setLoading] = useState(true)

  const loadProfile = useCallback(async (userId) => {
    try {
      if (!isConfigured) {
        const data = await fetchProfile('alex')
        setProfile(data)
        return
      }
      const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).single()
      if (error) throw error
      setProfile(data)
    } catch {
      // Fallback profile if Supabase profile not found
      setProfile({
        id: userId,
        username: 'alex',
        display_name: 'Alex Rivera',
        bio: 'Welcome to Gather!',
      })
    }
  }, [])

  useEffect(() => {
    if (!isConfigured) {
      loadProfile('demo-user-id').finally(() => setLoading(false))
      return
    }

    supabase.auth.getSession().then(({ data: { session }, error }) => {
      if (error) throw error
      setSession(session)
      if (session) loadProfile(session.user.id).finally(() => setLoading(false))
      else setLoading(false)
    }).catch(() => {
      setSession(null)
      setProfile(null)
      setLoading(false)
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session)
      if (session) loadProfile(session.user.id)
      else setProfile(null)
    })
    return () => subscription?.unsubscribe()
  }, [loadProfile])

  const signUp = async (email, password, username, displayName) => {
    if (!isConfigured) {
      const demoId = 'user-' + username
      const newSession = { user: { id: demoId, email } }
      setSession(newSession)
      setProfile({
        id: demoId,
        username,
        display_name: displayName || username,
        bio: `Hello, I'm @${username}!`,
      })
      return
    }
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { username, display_name: displayName } },
    })
    if (error) throw error
    return data
  }

  const signIn = async (email, password) => {
    if (!isConfigured) {
      const username = email.split('@')[0] || 'alex'
      setSession({ user: { id: 'demo-user-id', email } })
      loadProfile('demo-user-id')
      return
    }
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    return data
  }

  const signOut = async () => {
    if (isConfigured) {
      const { error } = await supabase.auth.signOut()
      if (error) throw error
    }
    setSession(null)
    setProfile(null)
  }

  const refreshProfile = () => {
    if (session?.user?.id) loadProfile(session.user.id)
  }

  const value = {
    session,
    user: session?.user ?? null,
    profile,
    loading,
    signUp,
    signIn,
    signOut,
    refreshProfile,
  }
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export const useAuth = () => useContext(AuthContext)
