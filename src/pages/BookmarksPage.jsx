import { useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { fetchBookmarks } from '../lib/api'
import { PageHeader, Spinner, EmptyState } from '../components/Shared'
import Tweet from '../components/Tweet'

export default function BookmarksPage() {
  const { user } = useAuth()
  const [bookmarks, setBookmarks] = useState(null)

  useEffect(() => {
    if (!user) return
    fetchBookmarks(user.id)
      .then(setBookmarks)
      .catch(() => setBookmarks([]))
  }, [user])

  return (
    <div>
      <PageHeader title="Bookmarks" subtitle={user ? `@${user.email?.split('@')[0] || 'alex'}` : ''} />
      {bookmarks === null ? (
        <Spinner />
      ) : bookmarks.length === 0 ? (
        <EmptyState title="Save Tweets for later" text="Don’t let the good ones fly away! Bookmark Tweets to easily find them again in the future." />
      ) : (
        bookmarks.map((t) => <Tweet key={t.id} item={t} />)
      )}
    </div>
  )
}
