# Session Summary: Neko Collaborative Browser Integration

## Context
User found [Neko](https://github.com/m1k1o/neko) — a self-hosted virtual browser running in Docker with WebRTC streaming — and wants to integrate it into Watchparty for collaborative browsing.

## Neko Architecture Discoveries
- **Version**: v3.1.4, Go server with legacy v2 bundled client
- **One container = one room**: single X display, one browser instance, shared by all viewers
- **Not multi-tenant**: needs `neko-rooms` or external orchestrator for multiple rooms
- **Stack**: Xorg + PulseAudio + Browser + Neko server + GStreamer + Supervisor as PID 1
- **Ports**: TCP 8080 (HTTP/WS), UDP 52000-52100 (WebRTC ICE)
- **Resources**: 4-8 vCPU, 3-4 GB RAM per room; Chromium needs ~2 GB shared memory
- **DRM**: Chromium AMD64 images explicitly install Widevine (L3 only); Netflix/Disney+ may still reject
- **Auth**: `multiuser` provider (two shared passwords), `file` provider (persistent users), session tokens via cookie/Bearer/query
- **Embedding**: supports `embed=1` and `cast=1` query params for iframe use
- **API**: REST at `/api/*`, WebSocket at `/api/ws`, WebRTC via Pion v4

## Watchparty Architecture Discoveries
- **Web**: React/Vite SPA, Socket.IO room lifecycle, Jellyfin media library, HLS player
- **Backend**: Express server serving SPA + REST + Socket.IO + Jellyfin proxy + LiveKit signaling
- **LiveKit**: exclusively for party camera/microphone A/V (not browser streaming)
- **Flutter**: desktop-focused (macOS/Linux/Windows/iOS), has `flutter_webrtc` via LiveKit, no WebView dependency
- **Room model**: `stage: lobby | watching`, tied to Jellyfin `mediaItemId` — no concept of browser activity yet
- **Auth**: Jellyfin identity provider, HTTP-only session cookie
- **Deployment**: Docker Compose with Caddy (HTTPS), Coturn (TURN), LiveKit, Jellyfin, *arr stack

## Key Conflicts & Gaps
- **Room state model** assumes Jellyfin-only; needs a new `activity.kind` discriminator (`none | jellyfin | remote-browser`)
- **Flutter can't embed Neko via LiveKit** — Neko uses its own signaling, not LiveKit protocol
- **`publicSession()` leaks internal fields** (hostToken, deviceIds) — must harden before adding browser credentials
- **Socket.IO polling forced** in web client due to proxy WebSocket issues — must fix for Neko control signaling
- **No container provisioning** in Neko API — must build orchestrator or use `neko-rooms`
- **Static Compose insufficient** for multi-room — need dynamic container lifecycle

## Recommended Architecture
1. **Separate activity type**: `remote-browser` alongside `jellyfin`, not a fake media item
2. **Backend**: new browser service module provisions/attaches/stops Neko containers per party; stores only `instanceId/status/controllerUserId` (never Neko credentials)
3. **Web client**: embed Neko via same-origin authenticated iframe/proxy; keep LiveKit cameras + chat around it
4. **Flutter client**: build **native Neko client** using existing `flutter_webrtc` — implement Neko REST auth, WebSocket signaling, SDP/ICE exchange, `RTCVideoRenderer`, data-channel input, control events
5. **Single-controller lease**: replace broad `collaborativeControl` with one active driver model for browser input
6. **Lifecycle**: centralize teardown so browser instances can't leak after party end/expiry/host-loss

## Flutter Native Client Components
- `NekoClient`: HTTP auth → WebSocket signaling → `RTCPeerConnection` → `RTCDataChannel`
- `RTCVideoRenderer` for display
- Pointer/keyboard/touch mapping
- Control request/release UI
- Reconnection handling
- Platform support: macOS, Windows, Linux, iOS (touch → Neko pointer events)

## Recommended Evaluation Path
1. Run one pinned Chromium Neko container locally
2. Build standalone Flutter spike: auth → WebSocket → video/audio → render → input → reconnect
3. Verify across Windows, Linux, macOS, iOS
4. Test streaming sites and DRM behavior
5. Measure CPU, memory, latency, bandwidth
6. Then design party lifecycle and multi-container provisioning

## Security Requirements
- Unique short-lived credentials per browser party
- Authenticated bootstrap endpoint (no permanent Neko passwords in party state)
- Strict proxy log redaction
- Automatic container destruction on party end
- Isolated browser profiles/cookies
- Narrow provisioning API (never mount Docker socket in public app)

## Bottom Line
**Highly feasible**, especially on web. Primary risks: per-room infrastructure cost, DRM compatibility, and Flutter native client implementation effort. The existing `flutter_webrtc` runtime makes native Neko streaming achievable without WebViews.
