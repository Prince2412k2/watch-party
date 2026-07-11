import { T, TYPE, EASE } from '../theme'
import { Icon, Ic } from './Icon'

/**
 * Per-screen flush header. Sticks to the top of the shell's scroll region and
 * pads `var(--sa-t)` so content clears the (translucent) status bar. Props:
 *   title    — string or node (rendered at `title` scale)
 *   onBack   — if set, shows a back chevron (≥44px target)
 *   left     — custom left node (overrides onBack)
 *   right    — node(s) for the trailing action cluster
 *   subtitle — small line under the title (optional)
 *   large    — bigger `display` title, left-aligned hero style
 */
export function TopBar({ title, subtitle, onBack, left, right, large = false }: any = {}) {
  return (
    <header
      style={{
        background: T.bg,
        borderBottom: `1px solid ${T.line}`,
        position: 'sticky', top: 0, zIndex: 20,
        paddingTop: `calc(var(--sa-t) + 10px)`,
        paddingBottom: 12,
        paddingLeft: `calc(var(--sa-l) + 16px)`,
        paddingRight: `calc(var(--sa-r) + 16px)`,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, minHeight: 44 }}>
        {left ?? (onBack && (
          <TopBarButton onClick={onBack} label="Back">
            <Icon path={Ic.back} size={22} />
          </TopBarButton>
        ))}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            ...(large ? TYPE.display : TYPE.title),
            color: T.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>
            {title}
          </div>
          {subtitle && (
            <div style={{ ...TYPE.label, color: T.dim, marginTop: 2, fontWeight: 500 }}>{subtitle}</div>
          )}
        </div>
        {right && <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: '0 0 auto' }}>{right}</div>}
      </div>
    </header>
  )
}

// 44×44 circular flat action button for the top bar (and reusable elsewhere).
export function TopBarButton({ children, onClick, label, active = false, badge }: any = {}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      className="mob-press"
      style={{
        position: 'relative',
        width: 44, height: 44, borderRadius: 999,
        display: 'grid', placeItems: 'center',
        border: `1px solid ${T.line}`,
        background: active ? T.surface2 : T.surface,
        color: T.text,
        cursor: 'pointer', flex: '0 0 auto',
        transition: `background .15s ${EASE}, color .15s ${EASE}`,
      }}
    >
      {children}
      {badge}
    </button>
  )
}
