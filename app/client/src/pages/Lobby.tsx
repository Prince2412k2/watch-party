import { DotLottieReact } from '@lottiefiles/dotlottie-react'
import { navigate } from '../router'

export default function Lobby({ partyId }: { partyId?: string } = {}) {
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
        <div style={{ width: 'clamp(170px, 25vh, 240px)', aspectRatio: '1', marginBottom: 18 }}>
          <DotLottieReact
            src="/watch_party.lottie"
            autoplay
            loop
            style={{ width: '100%', height: '100%' }}
          />
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
