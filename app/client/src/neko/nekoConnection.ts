// Framework-agnostic Neko WS+WebRTC client, ported from
// neko/client/src/neko/base.ts + index.ts (heartbeat wiring). We speak the
// protocol directly instead of embedding Neko's bundled Vue client so we can
// authenticate with our own per-user session token (?token=) rather than the
// bundled client's ?password=&username= URL params.
//
// NOTE: the vendored neko/client/ tree is v2.5.0 (legacy protocol) — its
// base.ts never sends a request to trigger media. The actual server we run
// is v3, whose signalRequest handler (server/internal/websocket/handler/
// signal.go) only creates the WebRTC peer and sends signal/provide once it
// receives `signal/request` from the client. We send that ourselves right
// after system/init, using the v3 wire shape (server/pkg/types/message
// SignalRequest: {video:{disabled?,selector?,auto?}, audio:{disabled?}}) —
// all fields optional, so an empty object per side takes the server's
// defaults (first available video stream, audio enabled).

const OPCODE = {
  MOVE: 0x01,
  SCROLL: 0x02,
  KEY_DOWN: 0x03,
  KEY_UP: 0x04,
} as const

const EVENT = {
  SYSTEM_INIT: 'system/init',
  SIGNAL_OFFER: 'signal/offer',
  SIGNAL_ANSWER: 'signal/answer',
  SIGNAL_PROVIDE: 'signal/provide',
  SIGNAL_CANDIDATE: 'signal/candidate',
  SIGNAL_REQUEST: 'signal/request',
  CLIENT_HEARTBEAT: 'client/heartbeat',
  SCREEN_RESOLUTION: 'screen/resolution',
} as const

export interface ScreenResolution {
  width: number
  height: number
  rate?: number
}

interface SystemInitPayload {
  heartbeat_interval: number
}

interface SignalProvidePayload {
  id: string
  lite: boolean
  ice: RTCIceServer[]
  sdp: string
}

interface SignalOfferPayload {
  sdp: string
}

interface SignalAnswerPayload {
  sdp: string
}

export interface NekoConnectionOptions {
  wsUrl: string
  token: string
  onStream?: (stream: MediaStream) => void
  onResolution?: (resolution: ScreenResolution) => void
  onConnected?: () => void
  onDisconnected?: (err?: Error) => void
}

export class NekoConnection {
  private opts: NekoConnectionOptions
  private ws?: WebSocket
  private wsHeartbeat?: number
  private peer?: RTCPeerConnection
  private channel?: RTCDataChannel
  private connectTimeout?: number
  private candidates: RTCIceCandidateInit[] = []
  private iceState: RTCIceConnectionState = 'disconnected'
  private closed = false

  constructor(opts: NekoConnectionOptions) {
    this.opts = opts
  }

  get socketOpen() {
    return !!this.ws && this.ws.readyState === WebSocket.OPEN
  }

  get peerConnected() {
    return !!this.peer && ['connected', 'checking', 'completed'].includes(this.iceState)
  }

  get connected() {
    return this.socketOpen && this.peerConnected
  }

  connect() {
    if (this.socketOpen) return

    const url = `${this.opts.wsUrl}?token=${encodeURIComponent(this.opts.token)}`
    this.ws = new WebSocket(url)
    this.ws.onmessage = this.onMessage
    this.ws.onerror = () => {}
    this.ws.onclose = () => this.handleDisconnected(new Error('websocket closed'))
    this.connectTimeout = window.setTimeout(() => this.handleDisconnected(new Error('connection timeout')), 15000)
  }

  disconnect() {
    this.closed = true

    if (this.connectTimeout) {
      clearTimeout(this.connectTimeout)
      this.connectTimeout = undefined
    }
    if (this.wsHeartbeat) {
      clearInterval(this.wsHeartbeat)
      this.wsHeartbeat = undefined
    }
    if (this.ws) {
      this.ws.onmessage = null
      this.ws.onerror = null
      this.ws.onclose = null
      try { this.ws.close() } catch {}
      this.ws = undefined
    }
    if (this.channel) {
      this.channel.onmessage = null
      this.channel.onerror = null
      this.channel.onclose = null
      try { this.channel.close() } catch {}
      this.channel = undefined
    }
    if (this.peer) {
      this.peer.onconnectionstatechange = null
      this.peer.onsignalingstatechange = null
      this.peer.oniceconnectionstatechange = null
      this.peer.ontrack = null
      this.peer.onicecandidate = null
      this.peer.onnegotiationneeded = null
      try { this.peer.close() } catch {}
      this.peer = undefined
    }
    this.iceState = 'disconnected'
    this.candidates = []
  }

  sendData(event: 'wheel' | 'mousemove', data: { x: number; y: number }): void
  sendData(event: 'mousedown' | 'mouseup' | 'keydown' | 'keyup', data: { key: number }): void
  sendData(event: string, data: any): void {
    if (!this.connected || !this.channel) return

    let buffer: ArrayBuffer
    let payload: DataView
    switch (event) {
      case 'mousemove':
        buffer = new ArrayBuffer(7)
        payload = new DataView(buffer)
        payload.setUint8(0, OPCODE.MOVE)
        payload.setUint16(1, 4, true)
        payload.setUint16(3, data.x, true)
        payload.setUint16(5, data.y, true)
        break
      case 'wheel':
        buffer = new ArrayBuffer(7)
        payload = new DataView(buffer)
        payload.setUint8(0, OPCODE.SCROLL)
        payload.setUint16(1, 4, true)
        payload.setInt16(3, data.x, true)
        payload.setInt16(5, data.y, true)
        break
      case 'keydown':
      case 'mousedown':
        buffer = new ArrayBuffer(11)
        payload = new DataView(buffer)
        payload.setUint8(0, OPCODE.KEY_DOWN)
        payload.setUint16(1, 8, true)
        payload.setBigUint64(3, BigInt(data.key), true)
        break
      case 'keyup':
      case 'mouseup':
        buffer = new ArrayBuffer(11)
        payload = new DataView(buffer)
        payload.setUint8(0, OPCODE.KEY_UP)
        payload.setUint16(1, 8, true)
        payload.setBigUint64(3, BigInt(data.key), true)
        break
      default:
        return
    }

    this.channel.send(buffer)
  }

  private onMessage = async (e: MessageEvent) => {
    let msg: any
    try {
      msg = JSON.parse(e.data)
    } catch {
      return
    }
    // Server envelope is {event, payload:{...}} (types.WebSocketMessage), not
    // a flat object — the real fields live under the nested `payload` key.
    const { event, payload } = msg

    switch (event) {
      case EVENT.SYSTEM_INIT: {
        const { heartbeat_interval } = payload as SystemInitPayload
        if (heartbeat_interval > 0) {
          if (this.wsHeartbeat) clearInterval(this.wsHeartbeat)
          this.wsHeartbeat = window.setInterval(() => this.sendMessage(EVENT.CLIENT_HEARTBEAT), heartbeat_interval * 1000)
        }
        // v3 only creates the WebRTC peer and sends signal/provide once we
        // ask for it — request the default video/audio stream now.
        this.sendMessage(EVENT.SIGNAL_REQUEST, { video: {}, audio: {}, auto: false })
        break
      }
      case EVENT.SIGNAL_PROVIDE: {
        const { sdp, lite, ice } = payload as SignalProvidePayload
        await this.createPeer(lite, ice)
        await this.setRemoteOffer(sdp)
        break
      }
      case EVENT.SIGNAL_OFFER: {
        const { sdp } = payload as SignalOfferPayload
        await this.setRemoteOffer(sdp)
        break
      }
      case EVENT.SIGNAL_ANSWER: {
        const { sdp } = payload as SignalAnswerPayload
        if (this.peer) await this.peer.setRemoteDescription({ type: 'answer', sdp })
        break
      }
      case EVENT.SIGNAL_CANDIDATE: {
        // SignalCandidate embeds webrtc.ICECandidateInit directly (Go struct
        // embedding) — the candidate fields are the payload itself, not a
        // JSON-stringified `data` wrapper.
        const candidate = payload as RTCIceCandidateInit
        if (this.peer) {
          try { await this.peer.addIceCandidate(candidate) } catch {}
        } else {
          this.candidates.push(candidate)
        }
        break
      }
      case EVENT.SCREEN_RESOLUTION: {
        const { width, height, rate } = payload as ScreenResolution
        this.opts.onResolution?.({ width, height, rate })
        break
      }
      default:
        break
    }
  }

  private sendMessage(event: string, payload?: any) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return
    // Server decodes {event, payload} (types.WebSocketMessage) — payload must
    // be nested, not spread flat onto the envelope.
    this.ws.send(JSON.stringify({ event, payload }))
  }

  private async createPeer(lite: boolean, servers: RTCIceServer[]) {
    if (!this.ws) return
    if (this.peerConnected) return

    this.peer = lite ? new RTCPeerConnection() : new RTCPeerConnection({ iceServers: servers })

    this.peer.oniceconnectionstatechange = () => {
      if (!this.peer) return
      this.iceState = this.peer.iceConnectionState

      if (this.iceState === 'checking') {
        if (this.connectTimeout) {
          clearTimeout(this.connectTimeout)
          this.connectTimeout = undefined
        }
      } else if (this.iceState === 'connected') {
        if (this.connectTimeout) {
          clearTimeout(this.connectTimeout)
          this.connectTimeout = undefined
        }
        this.opts.onConnected?.()
      } else if (this.iceState === 'failed') {
        this.handleDisconnected(new Error('peer failed'))
      } else if (this.iceState === 'closed') {
        this.handleDisconnected(new Error('peer closed'))
      }
    }

    this.peer.ontrack = (event: RTCTrackEvent) => {
      const stream = event.streams[0]
      if (stream) this.opts.onStream?.(stream)
    }

    this.peer.onicecandidate = (event: RTCPeerConnectionIceEvent) => {
      if (!event.candidate || !this.ws) return
      this.sendMessage(EVENT.SIGNAL_CANDIDATE, event.candidate.toJSON())
    }

    this.peer.onnegotiationneeded = async () => {
      if (!this.peer || !this.ws) return
      const d = await this.peer.createOffer()
      await this.peer.setLocalDescription(d)
      this.sendMessage(EVENT.SIGNAL_OFFER, { sdp: d.sdp })
    }

    this.channel = this.peer.createDataChannel('data')
    this.channel.onerror = () => {}
    this.channel.onclose = () => this.handleDisconnected(new Error('peer data channel closed'))
  }

  private async setRemoteOffer(sdp: string) {
    if (!this.peer || !this.ws) return

    await this.peer.setRemoteDescription({ type: 'offer', sdp })

    for (const candidate of this.candidates) {
      try { await this.peer.addIceCandidate(candidate) } catch {}
    }
    this.candidates = []

    const d = await this.peer.createAnswer()
    // add stereo=1 to answer sdp to enable stereo audio for chromium
    d.sdp = d.sdp?.replace(/(stereo=1;)?useinbandfec=1/, 'useinbandfec=1;stereo=1')
    await this.peer.setLocalDescription(d)

    this.sendMessage(EVENT.SIGNAL_ANSWER, { sdp: d.sdp })
  }

  private handleDisconnected = (err?: Error) => {
    if (this.closed) return
    this.disconnect()
    this.opts.onDisconnected?.(err)
  }
}
