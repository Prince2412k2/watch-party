import { navigate } from '../router'

export default function Lobby({ partyId }: any = {}) {
  return (
    <div style={{
      position: 'fixed', inset: 0, background: 'var(--bg)',
      display: 'grid', placeItems: 'center', overflow: 'hidden',
    }}>
      <div style={{
        position: 'relative', textAlign: 'center',
        display: 'flex', flexDirection: 'column', alignItems: 'center',
        animation: 'in .4s cubic-bezier(.2,0,.1,1)',
      }}>
        {/* Sonar pulse — conveys live connection, not a generic spinner */}
        <div style={{ position: 'relative', width: 64, height: 64, marginBottom: 40 }}>
          {[0, 1, 2].map(i => (
            <span key={i} style={{
              position: 'absolute', inset: 0, borderRadius: '50%',
              border: '1.5px solid var(--accent)',
              animation: 'sonar 2.4s ease-out infinite',
              animationDelay: `${i * 0.8}s`,
            }} />
          ))}
          <span style={{
            position: 'absolute', top: '50%', left: '50%',
            width: 12, height: 12, borderRadius: '50%',
            background: 'var(--accent)', transform: 'translate(-50%,-50%)',
            boxShadow: '0 0 16px var(--accent-glow)',
          }} />
        </div>

        <div style={{
          fontSize: 11, fontWeight: 700, letterSpacing: '.22em',
          textTransform: 'uppercase', color: 'var(--text3)', marginBottom: 16,
        }}>
          Waiting room
        </div>

        <h1 style={{
          fontSize: 34, fontWeight: 700, letterSpacing: '-0.03em',
          lineHeight: 1.1, marginBottom: 12, maxWidth: 440,
        }}>
          The host hasn't<br/>started yet
        </h1>

        <p style={{
          fontSize: 15, lineHeight: 1.55, color: 'var(--text2)',
          maxWidth: 320, marginBottom: 40,
        }}>
          You'll be pulled in the moment they let you through.
        </p>

        {/* Party code as the concrete focal element */}
        {partyId && (
          <div style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 7,
            marginBottom: 44,
          }}>
            <span style={{
              fontSize: 10.5, fontWeight: 700, letterSpacing: '.18em',
              textTransform: 'uppercase', color: 'var(--text3)',
            }}>
              Party code
            </span>
            <span style={{
              fontSize: 26, fontWeight: 600, letterSpacing: '.14em',
              fontFamily: 'ui-monospace, "SF Mono", monospace',
              color: 'var(--text)',
            }}>
              {partyId}
            </span>
          </div>
        )}

        {/* Leave is an exit, not a primary action — keep it quiet */}
        <button
          onClick={() => navigate('/library')}
          style={{
            border: 'none', background: 'none', cursor: 'pointer',
            color: 'var(--text3)', fontSize: 14, fontWeight: 500,
            padding: '8px 16px', transition: 'color .15s',
          }}
          onMouseEnter={e => e.currentTarget.style.color = 'var(--text)'}
          onMouseLeave={e => e.currentTarget.style.color = 'var(--text3)'}
        >
          Leave party
        </button>
      </div>
    </div>
  )
}
