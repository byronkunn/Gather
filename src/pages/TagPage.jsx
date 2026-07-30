import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { fetchRelatedTags, fetchTag, fetchTagPosts } from '../lib/api'
import { compact } from '../lib/format'
import Tweet from '../components/Tweet'
import FollowTagButton from '../components/FollowTagButton'
import { EmptyState, PageHeader, Spinner } from '../components/Shared'

export default function TagPage() {
  const { tagName } = useParams()
  const { user } = useAuth()
  const [tab, setTab] = useState('latest')
  const [tag, setTag] = useState(null)
  const [posts, setPosts] = useState(null)
  const [relatedTags, setRelatedTags] = useState([])
  const [notFound, setNotFound] = useState(false)

  const normalizedTag = (tagName || '').replace(/^#/, '').toLowerCase()

  const loadTag = useCallback(async () => {
    setNotFound(false)
    try {
      const [tagData, related] = await Promise.all([
        fetchTag(normalizedTag, user?.id),
        fetchRelatedTags(normalizedTag),
      ])
      setTag(tagData)
      setRelatedTags(related)
    } catch {
      setNotFound(true)
    }
  }, [normalizedTag, user?.id])

  const loadPosts = useCallback(async () => {
    try {
      setPosts(await fetchTagPosts(normalizedTag, user?.id, tab))
    } catch {
      setPosts([])
    }
  }, [normalizedTag, tab, user?.id])

  useEffect(() => {
    setTag(null)
    setPosts(null)
    loadTag()
  }, [loadTag])

  useEffect(() => {
    setPosts(null)
    loadPosts()
  }, [loadPosts])

  if (notFound) {
    return (
      <div>
        <PageHeader title={`#${normalizedTag}`} back />
        <EmptyState title="Tag not found" text="Try another topic or hashtag." />
      </div>
    )
  }

  return (
    <div>
      <PageHeader title={`#${normalizedTag || 'tag'}`} subtitle={tag ? `${compact(tag.post_count || 0)} posts` : ''} back />

      {tag && (
        <section className="tag-hero">
          <div>
            <h2 className="tag-hero-title">#{tag.normalized_name}</h2>
            <div className="muted">{compact(tag.post_count || 0)} posts using this tag</div>
            {tag.description && <p className="tag-description">{tag.description}</p>}
          </div>
          <FollowTagButton tag={tag.normalized_name} initialFollowing={Boolean(tag.is_following)} onChange={(next) => setTag((current) => current ? { ...current, is_following: next } : current)} />
        </section>
      )}

      <div className="tabs">
        <button className={`tab ${tab === 'latest' ? 'active' : ''}`} onClick={() => setTab('latest')}>
          <span>Latest</span>
        </button>
        <button className={`tab ${tab === 'top' ? 'active' : ''}`} onClick={() => setTab('top')}>
          <span>Top</span>
        </button>
        <button className={`tab ${tab === 'media' ? 'active' : ''}`} onClick={() => setTab('media')}>
          <span>Media</span>
        </button>
      </div>

      {relatedTags.length > 0 && (
        <section className="tag-related-wrap">
          <div className="section-label">Related tags</div>
          <div className="tag-related-list">
            {relatedTags.map((related) => (
              <Link key={related.normalized_name} to={`/tags/${related.normalized_name}`} className="tag-chip-link">
                #{related.normalized_name}
              </Link>
            ))}
          </div>
        </section>
      )}

      {posts === null ? (
        <Spinner />
      ) : posts.length === 0 ? (
        <EmptyState title="No posts yet" text={`No posts found for #${normalizedTag} in this view.`} />
      ) : (
        posts.map((item, index) => <Tweet key={`${item.tweet.id}-${index}`} item={item} />)
      )}
    </div>
  )
}