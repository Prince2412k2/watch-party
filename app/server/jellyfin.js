const BASE = process.env.JELLYFIN_URL || 'http://localhost:8096'

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

export function authenticate(username, password, deviceId = 'watchparty-server') {
  return jfetch('/Users/AuthenticateByName', {
    method: 'POST',
    body: { Username: username, Pw: password },
    deviceId,
  })
}

export function getItems(token, userId, params = {}) {
  const qs = new URLSearchParams({
    IncludeItemTypes: 'Movie,Series',
    Recursive: 'true',
    Fields: 'MediaSources',
    ...params,
  })
  return jfetch(`/Users/${userId}/Items?${qs}`, { token })
}

export function getItemChildren(token, userId, parentId) {
  return jfetch(`/Users/${userId}/Items?ParentId=${parentId}&Fields=MediaSources`, { token })
}

// User's library views (Movies, Shows, Anime, …) — the top-level collections
export function getViews(token, userId) {
  return jfetch(`/Users/${userId}/Views`, { token })
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
    Fields: 'Overview,Genres,People,Studios,Taglines,Tags,ProviderIds,ProductionYear,PremiereDate,CommunityRating,CriticRating,OfficialRating,RunTimeTicks,MediaSources,MediaStreams,Width,Height',
  })
  return jfetch(`/Users/${userId}/Items/${itemId}?${qs}`, { token })
}

export function buildHlsUrl(itemId, { maxBitrate, abr } = {}) {
  const params = {
    MediaSourceId: itemId,
    VideoCodec: 'h264',
    AudioCodec: 'aac',
    // Without an explicit bitrate/channel count Jellyfin's ffmpeg falls back to
    // a low-bitrate AAC encode and a naive surround→stereo downmix, which is
    // what "muffled" sounds like. Pin a proper stereo bitrate explicitly —
    // everyone here listens through browser/laptop speakers or a 2-channel
    // WebRTC audio path anyway, so downmixing to 5.1 gains nothing.
    AudioBitRate: '256000',
    MaxAudioChannels: '2',
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

// All SyncPlay calls accept deviceId so Jellyfin associates them with the right session
export const syncPlay = {
  newGroup: (token, deviceId, groupName = 'watchparty') =>
    jfetch('/SyncPlay/New', { method: 'POST', token, deviceId, body: { GroupName: groupName } }),

  joinGroup: (token, deviceId, groupId) =>
    jfetch('/SyncPlay/Join', { method: 'POST', token, deviceId, body: { GroupId: groupId } }),

  leaveGroup: (token, deviceId) =>
    jfetch('/SyncPlay/Leave', { method: 'POST', token, deviceId }),

  setQueue: (token, deviceId, itemId, positionTicks = 0) =>
    jfetch('/SyncPlay/SetNewQueue', {
      method: 'POST', token, deviceId,
      body: { PlayingQueue: [itemId], PlayingItemPosition: 0, StartPositionTicks: positionTicks },
    }),

  play: (token, deviceId, positionTicks, when) =>
    jfetch('/SyncPlay/Unpause', { method: 'POST', token, deviceId, body: { PositionTicks: positionTicks, When: when } }),

  pause: (token, deviceId, positionTicks) =>
    jfetch('/SyncPlay/Pause', { method: 'POST', token, deviceId, body: { PositionTicks: positionTicks } }),

  seek: (token, deviceId, positionTicks) =>
    jfetch('/SyncPlay/Seek', { method: 'POST', token, deviceId, body: { PositionTicks: positionTicks } }),

  ready: (token, deviceId, positionTicks, isPlaying, when) =>
    jfetch('/SyncPlay/Ready', {
      method: 'POST', token, deviceId,
      body: { PositionTicks: positionTicks, IsPlaying: isPlaying, When: when },
    }),

  bufferingDone: (token, deviceId, positionTicks, isPlaying, when) =>
    jfetch('/SyncPlay/BufferingDone', {
      method: 'POST', token, deviceId,
      body: { PositionTicks: positionTicks, IsPlaying: isPlaying, When: when },
    }),
}

export { BASE }
