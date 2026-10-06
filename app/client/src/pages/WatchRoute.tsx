import Party from './Party.tsx'

/** One mount-stable party tree for desktop, phone and the floating player. */
export function WatchRoute({ path }: { path: string }) {
  const segment = path.slice('/party/'.length)
  const qs = new URLSearchParams(window.location.search)
  if (segment === 'new') {
    const audioParam = qs.get('audioStreamIndex')
    const subtitleParam = qs.get('subtitleStreamIndex')
    const audioStreamIndex = audioParam == null ? NaN : Number(audioParam)
    const subtitleStreamIndex = subtitleParam == null ? NaN : Number(subtitleParam)
    const resumePositionTicks = Number(qs.get('resumePositionTicks'))
    return <Party isNew itemId={qs.get('itemId') ?? undefined} initialShare={qs.get('share') === 'camera' ? 'camera' : qs.get('share') === 'microphone' ? 'microphone' : undefined}
      initialTracks={{
        mediaSourceId: qs.get('mediaSourceId') ?? undefined,
        audioStreamIndex: Number.isInteger(audioStreamIndex) ? audioStreamIndex : undefined,
        subtitleStreamIndex: Number.isInteger(subtitleStreamIndex) ? subtitleStreamIndex : undefined,
        resumePositionTicks: Number.isSafeInteger(resumePositionTicks) && resumePositionTicks > 0 ? resumePositionTicks : undefined,
      }} />
  }
  return <Party partyId={segment} />
}

export default WatchRoute
