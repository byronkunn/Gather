import { useEffect } from 'react'
import Icon from './Icons'

export default function Modal({ onClose, children, back = false }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [onClose])

  return (
    <div className="modal-overlay" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal" role="dialog" aria-modal="true">
        <button className="icon-btn modal-close" onClick={onClose} aria-label="Close">
          <Icon name={back ? 'back' : 'close'} size={20} />
        </button>
        {children}
      </div>
    </div>
  )
}
