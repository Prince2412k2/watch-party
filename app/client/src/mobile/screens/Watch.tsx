import Party from '../../pages/Party'

/**
 * Watch = WRAP, do not rebuild (MOBILE-SPEC §2.4). There is NO separate mobile
 * watch screen: pages/Party.jsx + components/Player.jsx already contain a
 * complete, phone-tuned watch UI gated on usePhone() (immersive 100dvh stage,
 * MobileBottomBar, MobileCameraStrip, ChatSheet, RotateHint, double-tap-seek),
 * and the sync path (useSyncPlay via SyncBridge) + LiveKit lifecycle are
 * correctness-critical and must NOT remount on rotation.
 *
 * `WatchRoute` is the SINGLE shared element for every `/party/*` URL. App.jsx
 * renders it ABOVE the phone branch so the exact same tree serves desktop and
 * phone — a usePhone() flip on rotation can never tear down a live session.
 *
 * Any mobile watch-screen polish is done ADDITIVELY inside the existing Party/
 * Player components (keeping desktop branches intact) — never forked into here.
 */
export function WatchRoute({ path }: { path: string }) {
  const segment = path.slice('/party/'.length)
  const qs = new URLSearchParams(window.location.search)
  if (segment === 'new') {
    const audioParam = qs.get('audioStreamIndex')
    const subtitleParam = qs.get('subtitleStreamIndex')
    const audioStreamIndex = audioParam == null ? NaN : Number(audioParam)
    const subtitleStreamIndex = subtitleParam == null ? NaN : Number(subtitleParam)
    return <Party isNew itemId={qs.get('itemId') ?? undefined}
      initialTracks={{
        audioStreamIndex: Number.isInteger(audioStreamIndex) ? audioStreamIndex : undefined,
        subtitleStreamIndex: Number.isInteger(subtitleStreamIndex) ? subtitleStreamIndex : undefined,
      }} />
  }
  return <Party partyId={segment} />
}

export default WatchRoute
