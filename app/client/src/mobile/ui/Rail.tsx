import { T, MONO, TYPE, SP } from '../theme'

/**
 * Horizontal swipeable rail. Header (title + optional mono count) over a
 * scroll-snap row that scrolls by SWIPE only — NO hover arrows (§5). The row is
 * the horizontal scroller (`overflow-x: auto`) so wide content never widens the
 * page. Children are laid out with `gap`; give them a fixed width.
 */
export function Rail({ title, count, action, children, gap = SP.md, padX = 16, style }: any = {}) {
  return (
    <section style={{ marginBottom: SP.xl, ...style }}>
      {(title || action) && (
        <header style={{
          display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
          gap: 12, padding: `0 ${padX}px`, marginBottom: SP.md,
        }}>
          <h2 style={{ ...TYPE.title, color: T.text, display: 'flex', alignItems: 'baseline', gap: 9 }}>
            {title}
            {count != null && (
              <span style={{ fontFamily: MONO, fontSize: 12, fontWeight: 600, color: T.faint, letterSpacing: '.06em' }}>
                {String(count).padStart(2, '0')}
              </span>
            )}
          </h2>
          {action}
        </header>
      )}
      <div
        className="mob-rail"
        style={{
          display: 'flex', gap,
          overflowX: 'auto', overflowY: 'hidden',
          scrollSnapType: 'x proximity',
          WebkitOverflowScrolling: 'touch',
          overscrollBehaviorX: 'contain',
          padding: `2px ${padX}px`,
          scrollPaddingLeft: padX,
        }}
      >
        {children}
      </div>
    </section>
  )
}

// A rail item that snaps to the start edge. Wrap posters/cards in this.
export function RailItem({ children, style }: any = {}) {
  return <div style={{ scrollSnapAlign: 'start', flex: '0 0 auto', ...style }}>{children}</div>
}
