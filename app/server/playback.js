import { getPlaybackInfo, normalizePlaybackInfo } from './jellyfin.js'

function pickSource(response, mediaSourceId) {
  const sources = Array.isArray(response?.MediaSources) ? response.MediaSources : []
  if (!sources.length) return null
  if (mediaSourceId) return sources.find(source => source?.Id === mediaSourceId) ?? sources[0]
  return sources[0]
}

function defaultIndex(streams) {
  return streams.find(stream => stream?.isDefault)?.index ?? streams[0]?.index ?? null
}

export async function refreshPlayback(session, {
  token,
  userId,
  itemId,
  mediaSourceId = session?.mediaSourceId ?? null,
  audioStreamIndex,
  subtitleStreamIndex,
  playSessionId = session?.playback?.playSessionId ?? null,
} = {}) {
  const response = await getPlaybackInfo(token, userId, itemId, {
    mediaSourceId,
    audioStreamIndex,
    subtitleStreamIndex,
    playSessionId,
  })

  const source = pickSource(response, mediaSourceId)
  const audioStreams = (source?.MediaStreams ?? []).filter(stream => stream?.Type === 'Audio')
  const subtitleStreams = (source?.MediaStreams ?? []).filter(stream => stream?.Type === 'Subtitle')
  const playback = normalizePlaybackInfo(response, {
    itemId,
    selectedAudioIndex: Number.isInteger(audioStreamIndex)
      ? audioStreamIndex
      : defaultIndex(audioStreams),
    selectedSubtitleIndex: Number.isInteger(subtitleStreamIndex)
      ? subtitleStreamIndex
      : (defaultIndex(subtitleStreams) ?? -1),
  })

  session.mediaSourceId = playback.mediaSourceId ?? session.mediaSourceId ?? null
  session.playback = {
    ...playback,
    sourceId: playback.mediaSourceId ?? null,
    streamUrl: playback.transcodingUrl || playback.directStreamUrl || null,
  }
  return session.playback
}

export function buildPlaybackChoices(playback) {
  const audioStreams = playback?.audioStreams ?? []
  const subtitleStreams = playback?.subtitleStreams ?? []
  return {
    audioStreams,
    subtitleStreams,
    selectedAudioIndex: playback?.selectedAudioIndex ?? null,
    selectedSubtitleIndex: playback?.selectedSubtitleIndex ?? null,
  }
}
