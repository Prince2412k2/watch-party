const BASE = process.env.JELLYFIN_URL || 'http://localhost:8096'

const BROWSER_PLAYBACK_PROFILE = {
  Name: 'Watchparty Web',
  MaxStreamingBitrate: 20000000,
  DirectPlayProfiles: [
    {
      Type: 'Video',
      Container: 'mp4,m4v,mov,mkv,webm,ts,mpeg,mpegts',
      AudioCodec: 'aac,mp3,opus,flac,vorbis,ac3,eac3,mp2',
      VideoCodec: 'h264,hevc,av1,vp8,vp9',
    },
    {
      Type: 'Audio',
      Container: 'mp3,aac,flac,ogg,oga,opus,wav',
      AudioCodec: 'aac,mp3,opus,flac,vorbis,ac3,eac3,mp2',
    },
  ],
  TranscodingProfiles: [
    {
      Type: 'Video',
      Container: 'hls',
      Protocol: 'hls',
      AudioCodec: 'aac,mp3,opus,flac,vorbis,ac3,eac3,mp2',
      VideoCodec: 'h264,hevc,av1,vp8,vp9',
      MaxAudioChannels: '2',
    },
  ],
  SubtitleProfiles: [
    { Format: 'vtt', Method: 'External' },
    { Format: 'srt', Method: 'External' },
  ],
}

function clientHeader(deviceId = 'watchparty-server') {
  return `MediaBrowser Client="Watchparty", Device="Server", DeviceId="${deviceId}", Version="1.0.0"`
}

async function jfetch(path, { token, method = 'GET', body, deviceId } = {}) {
  const header = clientHeader(deviceId)
  const auth = token ? `${header}, Token="${token}"` : header

  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Emby-Authorization': auth,
    },
    body: body ? JSON.stringify(body) : undefined,
  })

  if (!res.ok) {
    const text = await res.text().catch(() => '')
    throw Object.assign(new Error(`Jellyfin ${method} ${path} → ${res.status}`), { status: res.status, body: text })
  }

  const ct = res.headers.get('content-type') || ''
  return ct.includes('application/json') ? res.json() : res.text()
}

function proxyJellyfinUrl(url) {
  if (!url) return null
  try {
    const resolved = new URL(url, BASE)
    return `/jellyfin${resolved.pathname}${resolved.search}${resolved.hash}`
  } catch {
    return url.startsWith('/') ? `/jellyfin${url}` : url
  }
}

export function authenticate(username, password, deviceId = 'watchparty-server') {
  return jfetch('/Users/AuthenticateByName', {
    method: 'POST',
    body: { Username: username, Pw: password },
    deviceId,
  })
}

// Change a user's own password. Jellyfin verifies CurrentPw itself and 401s
// when it is wrong, which is what lets this run on the user's own token
// rather than needing an admin one.
export function changePassword(token, userId, currentPassword, newPassword) {
  return jfetch(`/Users/${userId}/Password`, {
    method: 'POST',
    token,
    body: { CurrentPw: currentPassword, NewPw: newPassword },
  })
}

// ── Playback reporting ──────────────────────────────────────────────────────
// What makes a watch history exist. Jellyfin keeps per-user progress (the
// `UserData` on every item) only for playback it was TOLD about: these three
// calls are the telling, and without them Resume, Next Up, the played flag and
// every progress bar in the app stay empty forever — which is exactly what they
// were, because nothing here called them until now.
//
// Crucially this is independent of how the bytes reach the player. Jellyfin does
// not check; it takes our word for the position. So the fact that we serve the
// file ourselves (`native.js` proxies `/Videos/:id/stream?static=true` behind a
// signed URL, bypassing Jellyfin's own session handshake) costs us nothing here
// — we just have to do the reporting the handshake would have done.
//
// All three run on the CALLER'S token, never an admin one. The session decides
// whose history moves; a body can't ask for someone else's.
export function reportPlaybackStart(token, body) {
  return jfetch('/Sessions/Playing', { method: 'POST', token, body })
}

export function reportPlaybackProgress(token, body) {
  return jfetch('/Sessions/Playing/Progress', { method: 'POST', token, body })
}

// The one that matters most: Jellyfin decides the resume position and the
// played flag from where playback STOPPED. A session that only ever reported
// progress and then vanished leaves the item mid-watched at whatever the last
// tick said, which is why this is sent on pause-to-background and on quit, not
// only on a tidy close.
export function reportPlaybackStopped(token, body) {
  return jfetch('/Sessions/Playing/Stopped', { method: 'POST', token, body })
}

export function getItems(token, userId, params = {}) {
  const qs = new URLSearchParams({
    IncludeItemTypes: 'Movie,Series',
    Recursive: 'true',
    // SortName explicitly rather than by omission: `orderByRecentlyWatched`
    // leaves the never-played tail in whatever order this returns, so "then
    // alphabetical" has to be a promise the query makes, not a default we
    // happen to be getting.
    SortBy: 'SortName',
    SortOrder: 'Ascending',
    Fields: 'MediaSources',
    ...params,
  })
  return jfetch(`/Users/${userId}/Items?${qs}`, { token })
}

export async function resolveMediaSourceId(token, userId, itemId) {
  const data = await getItems(token, userId, {
    Ids: itemId,
    IncludeItemTypes: 'Movie,Series,Episode',
    Fields: 'MediaSources',
  })
  const item = data.Items?.[0]
  if (!item) return null
  return item.MediaSources?.[0]?.Id ?? itemId
}

export function getItemChildren(token, userId, parentId) {
  return jfetch(`/Users/${userId}/Items?ParentId=${parentId}&Fields=MediaSources`, { token })
}

// User's library views (Movies, Shows, Anime, …) — the top-level collections
export function getViews(token, userId) {
  return jfetch(`/Users/${userId}/Views`, { token })
}

// Movie collections / franchises. Jellyfin models these as `BoxSet` items, which
// getItems() deliberately excludes (it asks for Movie,Series), so they need
// their own query rather than a parameter tweak.
//
// `ParentId` scopes them to one library view. Without it a BoxSet search is
// server-wide and the Movies tab would list collections belonging to Shows or
// any other library. `Recursive` is required because box sets do not sit at the
// top level of the view.
export function getCollections(token, userId, parentId, limit = 100) {
  const qs = new URLSearchParams({
    SortBy: 'SortName',
    SortOrder: 'Ascending',
    IncludeItemTypes: 'BoxSet',
    Recursive: 'true',
    Fields: 'PrimaryImageAspectRatio,SortName,Overview,Genres,ChildCount',
    ImageTypeLimit: '1',
    EnableImageTypes: 'Primary,Backdrop,Banner,Thumb',
    StartIndex: '0',
    Limit: String(limit),
  })
  if (parentId) qs.set('ParentId', parentId)
  return jfetch(`/Users/${userId}/Items?${qs}`, { token })
}

// The parts of one collection. Ordered by release date rather than SortName:
// a franchise reads chronologically, and a title-sorted Harry Potter puts
// "Chamber of Secrets" before "Philosopher's Stone".
//
// Asks for the full detail field set because the analog stage renders a part's
// description, rating, runtime and resume position inline while it is focused —
// there is no separate detail fetch to fill them in later.
export function getCollectionItems(token, userId, collectionId) {
  const qs = new URLSearchParams({
    ParentId: collectionId,
    SortBy: 'PremiereDate,SortName',
    SortOrder: 'Ascending',
    Fields: [
      'MediaSources', 'Overview', 'Genres', 'ProductionYear', 'PremiereDate',
      'UserData', 'People', 'OfficialRating', 'CommunityRating', 'RunTimeTicks',
    ].join(','),
    EnableImageTypes: 'Primary,Backdrop,Thumb',
  })
  return jfetch(`/Users/${userId}/Items?${qs}`, { token })
}

// Partially-watched items → "Continue Watching"
export function getResumeItems(token, userId, limit = 12) {
  const qs = new URLSearchParams({
    Limit: String(limit),
    MediaTypes: 'Video',
    Recursive: 'true',
    Fields: 'PrimaryImageAspectRatio,ProductionYear,UserData',
    EnableImageTypes: 'Primary,Backdrop,Thumb',
  })
  return jfetch(`/Users/${userId}/Items/Resume?${qs}`, { token })
}

// Next episode to watch for in-progress series → "Next Up"
export function getNextUp(token, userId, limit = 16) {
  const qs = new URLSearchParams({
    UserId: userId,
    Limit: String(limit),
    Fields: 'PrimaryImageAspectRatio,ProductionYear',
    EnableImageTypes: 'Primary,Backdrop,Thumb',
  })
  return jfetch(`/Shows/NextUp?${qs}`, { token })
}

// Recently added, optionally scoped to one library
export function getLatest(token, userId, parentId, limit = 20) {
  const qs = new URLSearchParams({
    Limit: String(limit),
    Fields: 'ProductionYear',
    EnableImageTypes: 'Primary',
    IncludeItemTypes: 'Movie,Series',
  })
  if (parentId) qs.set('ParentId', parentId)
  return jfetch(`/Users/${userId}/Items/Latest?${qs}`, { token })
}

// Full detail for the hero / item page
export function getItemDetail(token, userId, itemId) {
  const qs = new URLSearchParams({
    Fields: 'Overview,Genres,People,Studios,Taglines,Tags,ProviderIds,ProductionYear,PremiereDate,CommunityRating,CriticRating,OfficialRating,RunTimeTicks,MediaSources,MediaStreams,Width,Height,Trickplay',
  })
  return jfetch(`/Users/${userId}/Items/${itemId}?${qs}`, { token })
}

export function selectTrickplayProfile(item, mediaSourceId, targetWidth = 320) {
  const selectedSourceId = mediaSourceId ?? item?.MediaSources?.find(source => item?.Trickplay?.[source?.Id])?.Id
  if (!selectedSourceId || !item?.MediaSources?.some(source => source?.Id === selectedSourceId)) return null
  const profiles = item?.Trickplay?.[selectedSourceId]
  if (!profiles || typeof profiles !== 'object') return null

  const candidates = Object.entries(profiles)
    .map(([width, profile]) => normalizeTrickplayProfile(width, profile))
    .filter(Boolean)
    .sort((a, b) => Math.abs(a.width - targetWidth) - Math.abs(b.width - targetWidth) || a.width - b.width)
  const profile = candidates[0]
  return profile ? { mediaSourceId: selectedSourceId, ...profile } : null
}

export function getTrickplayProfile(item, mediaSourceId, width) {
  if (!item?.MediaSources?.some(source => source?.Id === mediaSourceId)) return null
  return normalizeTrickplayProfile(String(width), item?.Trickplay?.[mediaSourceId]?.[String(width)])
}

function normalizeTrickplayProfile(width, profile) {
  const normalizedWidth = Number(width)
  if (Number(profile?.Width) !== normalizedWidth) return null
  const values = {
    width: normalizedWidth,
    height: Number(profile?.Height),
    tileWidth: Number(profile?.TileWidth),
    tileHeight: Number(profile?.TileHeight),
    thumbnailCount: Number(profile?.ThumbnailCount),
    intervalMs: Number(profile?.Interval),
  }
  if (!Object.values(values).every(Number.isSafeInteger)) return null
  if (Object.values(values).some(value => value <= 0)) return null
  return {
    ...values,
    sheetCount: Math.ceil(values.thumbnailCount / (values.tileWidth * values.tileHeight)),
  }
}

export function getPlaybackInfo(token, userId, itemId, {
  mediaSourceId,
  audioStreamIndex,
  subtitleStreamIndex,
  playSessionId,
} = {}) {
  const qs = new URLSearchParams({ UserId: userId })
  const body = { DeviceProfile: BROWSER_PLAYBACK_PROFILE }
  if (mediaSourceId) body.MediaSourceId = mediaSourceId
  if (Number.isInteger(audioStreamIndex) && audioStreamIndex >= 0) body.AudioStreamIndex = audioStreamIndex
  if (Number.isInteger(subtitleStreamIndex)) body.SubtitleStreamIndex = subtitleStreamIndex
  if (playSessionId) body.PlaySessionId = playSessionId
  return jfetch(`/Items/${itemId}/PlaybackInfo?${qs}`, { token, method: 'POST', body })
}

export function normalizePlaybackInfo(response, {
  itemId = null,
  selectedAudioIndex = null,
  selectedSubtitleIndex = null,
} = {}) {
  const source = response?.MediaSources?.[0] ?? null
  const mediaStreams = Array.isArray(source?.MediaStreams) ? source.MediaStreams : []
  const audioStreams = mediaStreams
    .filter(stream => stream?.Type === 'Audio')
    .map(stream => ({
      index: stream.Index,
      type: stream.Type,
      codec: stream.Codec ?? null,
      language: stream.Language ?? null,
      displayTitle: stream.DisplayTitle ?? null,
      title: stream.Title ?? null,
      isDefault: !!stream.IsDefault,
      isForced: !!stream.IsForced,
      isExternal: !!stream.IsExternal,
      isHearingImpaired: !!stream.IsHearingImpaired,
      deliveryUrl: stream.DeliveryUrl ?? null,
    }))
  const subtitleStreams = mediaStreams
    .filter(stream => stream?.Type === 'Subtitle')
    .map(stream => ({
      index: stream.Index,
      type: stream.Type,
      codec: stream.Codec ?? null,
      language: stream.Language ?? null,
      displayTitle: stream.DisplayTitle ?? null,
      title: stream.Title ?? null,
      isDefault: !!stream.IsDefault,
      isForced: !!stream.IsForced,
      isExternal: !!stream.IsExternal,
      isHearingImpaired: !!stream.IsHearingImpaired,
      deliveryUrl: stream.DeliveryUrl ?? null,
    }))

  return {
    itemId,
    mediaSourceId: source?.Id ?? null,
    playSessionId: response?.PlaySessionId ?? null,
    mediaStreams,
    audioStreams,
    subtitleStreams,
    selectedAudioIndex: selectedAudioIndex ?? null,
    selectedSubtitleIndex: selectedSubtitleIndex ?? null,
    directStreamUrl: proxyJellyfinUrl(source?.DirectStreamUrl ?? null),
    transcodingUrl: proxyJellyfinUrl(source?.TranscodingUrl ?? null),
  }
}

export function buildHlsUrl(itemId, {
  mediaSourceId,
  audioStreamIndex,
  subtitleStreamIndex,
  maxBitrate,
  abr,
} = {}) {
  const params = {
    MediaSourceId: mediaSourceId ?? itemId,
    VideoCodec: 'h264',
    AudioCodec: 'aac',
    // Without an explicit bitrate/channel count Jellyfin's ffmpeg falls back to
    // a low-bitrate AAC encode and a naive surround→stereo downmix, which is
    // what "muffled" sounds like. Pin a proper stereo bitrate explicitly —
    // everyone here listens through browser/laptop speakers or a 2-channel
    // WebRTC audio path anyway, so downmixing to 5.1 gains nothing.
    AudioBitRate: '256000',
    MaxAudioChannels: '2',
    // Jellyfin omits its external subtitle renditions from an HLS master unless
    // this is explicitly enabled. hls.js can only populate the browser's
    // textTracks collection from renditions advertised in that manifest, so
    // without this flag the web player's subtitle menu is always empty even
    // when the media source has embedded or sidecar subtitles.
    EnableSubtitlesInManifest: 'true',
  }
  if (Number.isInteger(audioStreamIndex) && audioStreamIndex >= 0) {
    params.AudioStreamIndex = String(audioStreamIndex)
  }
  if (Number.isInteger(subtitleStreamIndex)) {
    params.SubtitleStreamIndex = String(subtitleStreamIndex)
  }
  if (abr) {
    // Adaptive (ABR) master: don't pin a single bitrate/resolution. Jellyfin's
    // master.m3u8 then emits a multi-variant ladder (several #EXT-X-STREAM-INF
    // renditions in one playlist) and hls.js picks the rung by bandwidth. We
    // still request a large ceiling so the top rung is the source's full res.
    // BreakOnNonKeyFrames lets each rendition switch at segment boundaries.
    params.MaxStreamingBitrate = '20000000'
    params.MaxWidth = '1920'
    params.BreakOnNonKeyFrames = 'true'
  } else if (maxBitrate) {
    // Single-bitrate transcode (legacy Phase-1.1 src-swap path): cap video
    // bitrate + resolution so a slow guest can keep up.
    params.VideoBitrate = String(maxBitrate)
    params.maxHeight = String(maxBitrate >= 3_000_000 ? 720 : maxBitrate >= 1_500_000 ? 480 : 360)
  }
  const qs = new URLSearchParams(params)
  // Route through the app's authenticated HLS proxy (/api/library/hls/*). That
  // route attaches the per-user Jellyfin api_key server-side and strips it from
  // the returned playlists, so the raw token never reaches the browser. Nested
  // playlist/segment URIs stay relative and resolve back through the same proxy.
  return `/api/library/hls/Videos/${itemId}/master.m3u8?${qs}`
}

// NOTE: this module used to also export a `syncPlay` client for Jellyfin's
// SyncPlay API. Commit 84e5885 replaced SyncPlay with the host-authority
// timeline engine in app/server/session.js, and nothing has called it since.
// Removed in #63 — the wire contract is app/shared/contracts/, not SyncPlay.

export { BASE }
