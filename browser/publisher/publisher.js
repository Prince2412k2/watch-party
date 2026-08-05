// Runs inside the container's publisher window. Captures the virtual screen —
// which shows the target browser, maximized — and publishes it into the party's
// existing LiveKit room as a screen-share track. Chromium does the capture,
// the encoding and the WebRTC; this file only configures it and reports back.
//
// Status is POSTed to the agent (same origin, loopback) rather than only logged,
// because app/server needs to know the difference between "still starting",
// "streaming" and "failed" to tell the party something truthful.

const LK = window.LivekitClient
let cfg

const logEl = document.getElementById('log')
const lines = []
function say(...args) {
  const msg = args.map(a => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')
  console.log('[publisher]', msg)
  lines.push(msg)
  logEl.textContent = lines.slice(-40).join('\n')
}

// Fire-and-forget: a failed report must never take down the stream, and the
// agent is on the same origin so this is not a CORS preflight.
function report(event, extra = {}) {
  fetch('/state', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ event, ...extra }),
  }).catch(() => {})
}

async function main() {
  cfg = await fetch('/config', { cache: 'no-store' }).then(response => {
    if (!response.ok) throw new Error('publisher config unavailable')
    return response.json()
  })
  say(`config ${cfg.w}x${cfg.h}@${cfg.fps} cap=${cfg.kbps}kbps`)
  if (!cfg.url || !cfg.token) throw new Error('missing lk / token query params')

  // adaptiveStream and dynacast are subscriber-side economies and this
  // participant only publishes. Simulcast is off deliberately: encoding three
  // layers of full-motion video is the single biggest CPU cost available to
  // avoid, and the container's budget is 4 of 8 shared vCPUs.
  const room = new LK.Room({ adaptiveStream: false, dynacast: false })

  room.on(LK.RoomEvent.Disconnected, reason => {
    say('room disconnected:', String(reason))
    report('fatal', { message: `disconnected: ${reason}` })
  })
  room.on(LK.RoomEvent.ConnectionStateChanged, state => say('connection state:', state))

  await room.connect(cfg.url, cfg.token)
  say(`connected to room "${room.name}" as "${room.localParticipant.identity}"`)

  const stream = await navigator.mediaDevices.getDisplayMedia({
    video: {
      width: { ideal: cfg.w },
      height: { ideal: cfg.h },
      frameRate: { ideal: cfg.fps, max: cfg.fps },
    },
    // Whole-screen capture on Linux hands back no audio, and asking for it can
    // fail the whole call. Audio comes from the PulseAudio loopback below.
    audio: false,
  })
  const videoTrack = stream.getVideoTracks()[0]
  if (!videoTrack) throw new Error('capture returned no video track')

  // The single most important line for perceived quality. Screen-share encoders
  // default to tuning for text and static content, which wrecks motion; 'motion'
  // tells the encoder to protect framerate and temporal smoothness instead —
  // and video is what this browser is for.
  videoTrack.contentHint = 'motion'
  say('captured video:', JSON.stringify(videoTrack.getSettings()))

  await room.localParticipant.publishTrack(videoTrack, {
    name: 'shared-browser',
    source: LK.Track.Source.ScreenShare,
    simulcast: false,
    // screenShareEncoding, NOT videoEncoding. livekit-client does
    //   if (isScreenShare) videoEncoding = options.screenShareEncoding
    // so for a ScreenShare source it discards videoEncoding outright and falls
    // back to its default ScreenSharePresets.h1080fps15 — which pins the stream
    // at exactly 15fps no matter what you asked for. Both are set here because
    // the source is what selects between them.
    screenShareEncoding: { maxBitrate: cfg.kbps * 1000, maxFramerate: cfg.fps },
    videoEncoding: { maxBitrate: cfg.kbps * 1000, maxFramerate: cfg.fps },
    // maxBitrate is also the fault-isolation boundary: this stream shares an
    // uplink with everyone's cameras, so it gets a ceiling rather than as much
    // as the encoder would like.
    degradationPreference: 'maintain-framerate',
  })
  say('published video track')

  const audioTrack = await captureAudio()
  if (audioTrack) {
    await room.localParticipant.publishTrack(audioTrack, {
      name: 'shared-browser-audio',
      source: LK.Track.Source.ScreenShareAudio,
    })
    say('published audio track')
  } else {
    say('WARN: no audio captured — the stream will be silent')
  }

  // Only now is there something for a viewer to see. Reporting earlier makes the
  // app tell the party "ready" while the room is still black.
  report('published')
  reportStats(room)
}

async function captureAudio() {
  // entrypoint.sh points the default PulseAudio source at a null sink's monitor
  // (republished through module-remap-source, because Chromium filters monitor
  // sources out of its input list), so plain getUserMedia picks up whatever the
  // target browser is playing.
  try {
    const mic = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    })
    return mic.getAudioTracks()[0] || null
  } catch (err) {
    say('getUserMedia audio failed:', String(err))
    return null
  }
}

function reportStats(room) {
  const publication = [...room.localParticipant.videoTrackPublications.values()][0]
  const sender = publication?.track?.sender
  if (!sender) return

  let previous = null
  setInterval(async () => {
    let outbound = null
    ;(await sender.getStats()).forEach(entry => {
      if (entry.type === 'outbound-rtp' && entry.kind === 'video') outbound = entry
    })
    if (!outbound) return

    let kbps = 0
    if (previous && outbound.timestamp > previous.timestamp) {
      kbps = Math.round(
        ((outbound.bytesSent - previous.bytesSent) * 8) / (outbound.timestamp - previous.timestamp)
      )
    }
    previous = outbound

    const stats = {
      kbps,
      res: `${outbound.frameWidth || 0}x${outbound.frameHeight || 0}`,
      fps: Math.round(outbound.framesPerSecond || 0),
      encoder: outbound.encoderImplementation || '?',
      limit: outbound.qualityLimitationReason || 'none',
    }
    say('TX ' + JSON.stringify(stats))
    report('stats', { stats })
  }, 5000)
}

main().catch(err => {
  const message = String(err && err.message ? err.message : err)
  say('FATAL', String(err && err.stack ? err.stack : err))
  report('fatal', { message })
})
