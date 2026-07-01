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

export function buildHlsUrl(itemId, token, { maxBitrate } = {}) {
  const params = {
    MediaSourceId: itemId,
    api_key: token,
    VideoCodec: 'h264',
    AudioCodec: 'aac',
  }
  if (maxBitrate) {
    // Cap video bitrate (and resolution to match) so a slow guest can keep up
    params.VideoBitrate = String(maxBitrate)
    params.maxHeight = String(maxBitrate >= 3_000_000 ? 720 : maxBitrate >= 1_500_000 ? 480 : 360)
  }
  const qs = new URLSearchParams(params)
  // Origin-relative so any client reaches Jellyfin via the app's /jellyfin proxy
  // (an absolute localhost URL would resolve to the *client's* machine).
  return `/jellyfin/Videos/${itemId}/master.m3u8?${qs}`
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
