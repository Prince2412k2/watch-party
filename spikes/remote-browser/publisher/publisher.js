// Runs inside the container's browser. Captures the target (whole screen, or a
// named tab) and publishes it into an existing LiveKit room as a screen-share
// track. Chromium does the encoding and the WebRTC; this file only configures it.
//
// Everything logged here reaches `docker logs` because chromium is started with
// --enable-logging=stderr.

const LK = window.LivekitClient
const q = new URLSearchParams(location.search)

const cfg = {
  url: q.get('lk'),
  token: q.get('token'),
  mode: q.get('mode') || 'screen',
  codec: q.get('codec') || 'vp8',
  kbps: Number(q.get('kbps') || 2500),
  fps: Number(q.get('fps') || 30),
  w: Number(q.get('w') || 1280),
  h: Number(q.get('h') || 720),
}

const logEl = document.getElementById('log')
const lines = []
function say(...args) {
  const msg = args.map(a => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')
  console.log('[publisher]', msg)
  lines.push(msg)
  logEl.textContent = lines.slice(-40).join('\n')
}

async function main() {
  say(`config mode=${cfg.mode} codec=${cfg.codec} ${cfg.w}x${cfg.h}@${cfg.fps} cap=${cfg.kbps}kbps`)
  if (!cfg.url || !cfg.token) throw new Error('missing lk / token query params')

  // adaptiveStream and dynacast are subscriber-side economies; this participant
  // only publishes, and simulcast is off deliberately — encoding three layers of
  // full-motion video is the single biggest CPU cost we can avoid, and "keep it
  // lightweight" outranks per-viewer layer selection for a first cut.
  const room = new LK.Room({ adaptiveStream: false, dynacast: false })

  room.on(LK.RoomEvent.Disconnected, r => say('room disconnected:', String(r)))
  room.on(LK.RoomEvent.ConnectionStateChanged, s => say('connection state:', s))

  await room.connect(cfg.url, cfg.token)
  say(`connected to room "${room.name}" as "${room.localParticipant.identity}"`)

  const stream = await capture()
  const videoTrack = stream.getVideoTracks()[0]
  if (!videoTrack) throw new Error('capture returned no video track')

  // The single most important line for video quality. Screen-share encoders
  // default to tuning for text/static content, which wrecks motion; 'motion'
  // tells the encoder to protect framerate and temporal smoothness instead.
  videoTrack.contentHint = 'motion'

  const settings = videoTrack.getSettings()
  say('captured video:', JSON.stringify(settings))

  await room.localParticipant.publishTrack(videoTrack, {
    name: 'remote-browser',
    source: LK.Track.Source.ScreenShare,
    simulcast: false,
    videoCodec: cfg.codec,
    // screenShareEncoding, NOT videoEncoding. livekit-client does
    //   if (isScreenShare) videoEncoding = options.screenShareEncoding
    // so for a ScreenShare source it discards videoEncoding outright and falls
    // back to its default ScreenSharePresets.h1080fps15 — which pins the stream
    // at exactly 15fps no matter what you asked for. Both are set here because
    // the source is what selects between them.
    screenShareEncoding: { maxBitrate: cfg.kbps * 1000, maxFramerate: cfg.fps },
    videoEncoding: { maxBitrate: cfg.kbps * 1000, maxFramerate: cfg.fps },
    degradationPreference: 'maintain-framerate',
  })
  say('published video track')

  const audioTrack = await resolveAudio(stream)
  if (audioTrack) {
    await room.localParticipant.publishTrack(audioTrack, {
      name: 'remote-browser-audio',
      source: LK.Track.Source.ScreenShareAudio,
    })
    say('published audio track:', JSON.stringify(audioTrack.getSettings()))
  } else {
    say('AUDIO: none captured — record the audio probe as FAIL/N-A')
  }

  reportStats(room)
}

async function capture() {
  // In screen mode chromium resolves the source from
  // --auto-select-desktop-capture-source, so no picker appears. In tab mode the
  // equivalent flag is --auto-select-tab-capture-source-by-title.
  const video = {
    width: { ideal: cfg.w },
    height: { ideal: cfg.h },
    frameRate: { ideal: cfg.fps, max: cfg.fps },
  }
  // Tab capture hands back the tab's audio; whole-screen capture on Linux does
  // not, and asking for it can fail the whole call.
  const audio = cfg.mode === 'tab'
  say(`requesting getDisplayMedia(audio=${audio})`)
  return navigator.mediaDevices.getDisplayMedia({ video, audio })
}

async function resolveAudio(stream) {
  const fromDisplay = stream.getAudioTracks()[0]
  if (fromDisplay) {
    say('audio came from the capture itself')
    return fromDisplay
  }
  // Screen mode: entrypoint.sh pointed the default PulseAudio source at a null
  // sink's monitor, so plain getUserMedia picks up whatever the browser plays.
  try {
    say('no audio in capture; trying getUserMedia on the pulse monitor')
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
  const pub = [...room.localParticipant.videoTrackPublications.values()][0]
  const sender = pub?.track?.sender
  if (!sender) { say('no RTCRtpSender — stats unavailable'); return }

  // Audio level, so "I hear nothing" can be split into "nothing was captured"
  // versus "the viewer never started playback". Without this the two are
  // indistinguishable from the logs.
  const aSender = [...room.localParticipant.audioTrackPublications.values()][0]?.track?.sender
  if (aSender) {
    setInterval(async () => {
      let src = null
      ;(await aSender.getStats()).forEach(s => { if (s.type === 'media-source' && s.kind === 'audio') src = s })
      if (src) {
        say('AUDIO level=' + (src.audioLevel ?? 0).toFixed(4)
          + ' energy=' + (src.totalAudioEnergy ?? 0).toFixed(3)
          + (src.audioLevel > 0.0005 ? ' (sound present)' : ' (SILENT)'))
      }
    }, 5000)
  }

  let prev = null
  setInterval(async () => {
    const report = await sender.getStats()
    let out = null, src = null
    report.forEach(s => {
      if (s.type === 'outbound-rtp' && s.kind === 'video') out = s
      if (s.type === 'media-source' && s.kind === 'video') src = s
    })
    if (!out) return

    let kbps = 0
    if (prev && out.timestamp > prev.timestamp) {
      kbps = Math.round(((out.bytesSent - prev.bytesSent) * 8) / (out.timestamp - prev.timestamp))
    }
    prev = out

    say('TX ' + JSON.stringify({
      kbps,
      res: `${out.frameWidth || 0}x${out.frameHeight || 0}`,
      fpsSent: Math.round(out.framesPerSecond || 0),
      fpsCaptured: Math.round(src?.framesPerSecond || 0),
      encoder: out.encoderImplementation || '?',
      qualityLimit: out.qualityLimitationReason || 'none',
      keyframes: out.keyFramesEncoded || 0,
      // Sent by the receiver, not us. A climbing keyframe count with plis also
      // climbing means loss is forcing recovery keyframes — which cost bitrate,
      // which causes more loss. Without these two the storm looks like an encoder
      // bug rather than a network one.
      plis: out.pliCount || 0,
      nacks: out.nackCount || 0,
      rtt: out.roundTripTime !== undefined ? Math.round(out.roundTripTime * 1000) : '?',
    }))
  }, 2000)
}

main().catch(err => {
  say('FATAL', String(err && err.stack ? err.stack : err))
})
