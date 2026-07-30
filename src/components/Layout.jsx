import { Outlet, useLocation } from 'react-router-dom'
import { useUi } from '../context/UiContext'
import Sidebar from './Sidebar'
import MobileNav from './MobileNav'
import RightPanel from './RightPanel'
import Modal from './Modal'
import TweetComposer from './TweetComposer'
import Tweet from './Tweet'

export default function Layout() {
  const { composeState, closeCompose } = useUi()
  const location = useLocation()
  const isMessages = location.pathname.startsWith('/messages')

  return (
    <div className={`app-shell ${isMessages ? 'messages-shell' : ''}`}>
      <Sidebar compact={isMessages} />
      <main className="main-column">
        <Outlet />
      </main>
      {!isMessages && <RightPanel />}
      <MobileNav />
      {composeState && (
        <Modal onClose={closeCompose}>
          <div className="compose-modal">
            {composeState.replyTo && (
              <div className="compose-modal-parent">
                <Tweet item={composeState.replyTo} />
              </div>
            )}
            <TweetComposer
              replyTo={composeState.replyTo}
              autoFocus
              onPosted={() => closeCompose()}
            />
          </div>
        </Modal>
      )}
    </div>
  )
}
