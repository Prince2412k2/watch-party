# iOS PWA media feasibility — Watchparty

Research date: 2026-10-05. Based on the current repository, WebKit documentation,
Jellyfin documentation, and current MDN browser compatibility data. This is a
feasibility assessment and implementation proposal, not an iPhone-tested release.

## Decision

An installed iOS PWA can provide an immersive movie screen with floating cameras,
foreground resumable local downloads, and playback of broad library formats through
server-side conversion. It cannot promise unrestricted native codec decoding,
background movie downloads after suspension, or complete control over system UI.

Recommended initial target: iOS 17+ Home Screen installation, with capability checks
for every storage/media API. Older versions need a separately verified fallback.

| Requirement | Feasibility | Recommended mechanism |
| --- | --- | --- |
| Movie fills app viewport with floating participant cameras | Yes, while app is foreground | Inline video + DOM overlays in standalone PWA |
| iPhone native video fullscreen with our DOM cameras on top | No supported general mechanism | Keep movie inline instead |
| Save movies locally and replay in app | Yes, with new offline architecture | OPFS media + IndexedDB metadata + cached app shell |
| Continue in-app downloads after lock/background/termination | Cannot guarantee | Persist progress and resume on return |
| Play broad server library formats | Yes, within server decoder/conversion support | Direct play, remux, audio conversion, or full transcode |
| Decode every original codec locally, including offline | No practical universal guarantee | Download an already compatible rendition |

## 1. Fullscreen and floating cameras

### Existing implementation

- `app/client/public/manifest.webmanifest` uses `display: standalone`, orientation
  `any`, and `display_override: [standalone, fullscreen]`.
- `app/client/index.html` already sets `viewport-fit=cover`, Apple standalone
  metadata, and the black-translucent status-bar style.
- `app/client/src/pages/Party.tsx:430-511` feature-detects element fullscreen and
  otherwise keeps the entire watch stage in a fixed `100dvh` / `100dvw` layout.
  It deliberately avoids iPhone native video fullscreen.
- `Party.tsx:740-839` already supplies a draggable/resizable mobile camera popup
  containing local and remote camera tiles. It remains visible when player
  controls hide; its bounds change to use the available space.
- `app/client/src/components/CameraTile.tsx:66` and `Player.tsx:225` use
  `playsInline`. Camera tracks are attached through LiveKit.

### Platform boundary

Current MDN compatibility data says unprefixed element fullscreen is available
from Safari 16.4 on iPad, but not iPhone. WebKit's 16.4 release announcement also
explicitly lists macOS and iPadOS for this API.

On iPhone, native video fullscreen takes over the video presentation; arbitrary
page overlays do not accompany it. An installed standalone PWA removes Safari
toolbars, allowing the existing full-viewport DOM presentation to deliver the
desired experience. Status-bar/home-indicator behavior remains OS-controlled.
Manifest fullscreen settings do not override this limitation. The existing
`display_override` list also prefers standalone over fullscreen.

System picture-in-picture is a different requirement: do not promise a camera
popup over other apps or the entire movie/camera DOM composition in system PiP.

### Recommended work

1. Verify the existing layout on physical iPhone and iPad in Home Screen mode.
2. Recognize standalone mode using `matchMedia('(display-mode: standalone)')`
   and the Apple `navigator.standalone` fallback; explain installation in Safari.
3. Re-clamp popup geometry after rotation, viewport/safe-area changes, and control
   bar expansion. Current initial popup geometry is computed only on mount.
4. Preserve the existing capture-toggle/sync guard. Verify movie audio together
   with participant audio, Bluetooth routes, interruptions, and camera switching.
5. Feature-detect orientation locking; current Safari compatibility data reports
   `screen.orientation.lock()` unsupported. Keep manual rotation guidance.

No replacement conferencing service is required for this feature.

## 2. Local downloading and offline playback

### Existing implementation and gaps

- `analog/movieDetails.ts` and `analog/showDetails.ts` gate local download actions
  on `IS_NATIVE`; web downloads are not implemented by enabling a button alone.
- The existing browser `/downloads` experience tracks server-side acquisition
  through Servarr/qBittorrent. That is separate from storing movies on an iPhone.
- No app service-worker registration or offline shell was found in the client.
- `context/AuthContext.tsx` fetches `/api/auth/me` at startup and sets the user to
  null on network failure. A cold offline launch needs a deliberate local library
  path rather than redirecting a previously authenticated user to online login.
- `app/server/native.js` already has an original-file, range-capable delivery
  endpoint with expiring opaque URLs. It does not produce iOS-compatible media.

### Supported foundation

WebKit documents Origin Private File System (OPFS) support from iOS 15.2, with
`getFile()` from 15.4. OPFS stores data privately for the origin; it is not a
user-visible directory in the Files app. Dedicated-worker sync access handles
offer incremental writes without buffering an entire movie in JavaScript memory.

Safari 17 introduced full Storage API support, including `estimate()`,
`persisted()`, and `persist()`. WebKit documents standalone Home Screen apps as
having browser-equivalent quotas: up to 60% of total disk per origin, subject to
actual space, overall quota, and storage policy. This is an upper bound, not
reserved free space. Persistence requests are heuristic and may be denied.

Safari/iOS does not support Background Fetch. Service workers are not permanent
background processes; installing a PWA does not make long downloads reliable
while the app is suspended. Plan foreground transfers with restart-safe resume.

### Proposed architecture

1. **Stable rendition:** prepare an immutable, compatible MP4 on the server,
   with video H.264 8-bit, AAC audio, and fast-start metadata for the baseline.
   Reuse originals only when compatible; remux or convert other sources. Return
   rendition ID/version, byte length, duration, track metadata, and a strong
   validator or integrity manifest. Retain the rendition long enough to resume.
2. **Transfer worker:** stream bounded byte ranges to OPFS; validate response
   status, Content-Range and representation identity. Flush verified bytes before
   checkpointing progress in IndexedDB. Recover incomplete checkpoints after a
   crash; renew delivery URLs without changing representation. Pause/cancel,
   bounded retry, storage-full errors, and source-change handling are required.
3. **Local library:** store item artwork, metadata, selected downloadable tracks,
   subtitle files, and progress separately from remote acquisition jobs. Partition
   by account/server. Request persistence and expose local storage/deletion UI.
4. **Playback:** first prototype `getFile()` → object URL → regular inline video.
   Close the write handle before exposing completed media and revoke obsolete
   URLs. Test multi-gigabyte files and arbitrary seeks on physical iOS. If needed,
   use a same-origin service-worker media URL serving bounded OPFS slices with
   correct 200/206/416 semantics. Do not concatenate the movie into one RAM buffer.
5. **Offline shell:** add a versioned service worker for app assets and an offline
   library/player route. Keep online authentication separate from access to
   previously downloaded local media. Cache explicitly chosen local metadata;
   avoid indiscriminately caching authenticated APIs or expiring stream URLs.
6. **Party integration:** online party participants may each play their compatible
   local rendition while Socket.IO and LiveKit remain connected. Fully offline
   replay is solo: live cameras, chat, and remote synchronization need networking.
   Preserve canonical media identity and time zero across local/remote sources.

For the first release, download to completion before local playback. Concurrent
play-while-downloading adds locking and missing-range scheduling complexity.

Saving/exporting to Files is a separate feature. Current Safari compatibility data
does not support `showSaveFilePicker()`. Browser download/share flows can be
investigated, but do not give the PWA persistent general access to arbitrary Files
directories, or automatically turn an exported file into an in-app download.

Prefer a stable MP4 over caching live Jellyfin HLS sessions for the first version.
Offline HLS must preserve/rewrite playlists, variants, segments, init data,
subtitles and any keys, and validate Safari's native playback delivery path.

## 3. Playing any codec

### App-specific findings

`app/server/jellyfin.js:3-34` advertises a single broad browser profile including
MKV, MPEG, AV1, HEVC and multiple audio codecs. This is not an accurate guarantee
for all iOS devices. `getPlaybackInfo()` uses that same profile for every caller.

`buildHlsUrl():356-407` already asks for H.264/AAC, but the main
`/api/library/hls-url` path in `library.js:339-367` prefers URLs supplied by
PlaybackInfo. Merely changing the fallback does not constrain those URLs.
`playback.js:19-56` also stores a shared negotiated stream URL in room state.
Negotiation should be per participant/device while media identity, selected
tracks and authoritative playback time remain shared.

`media-converter/README.md:89-100` describes a remux-oriented policy: H.264,
HEVC, AV1 and MPEG-4 video are copied, other video codecs are not transcoded,
and unsupported bitmap subtitles can be omitted. An MP4 extension therefore
does not establish universal iPhone compatibility or complete subtitle retention.

### Recommended policy

- Establish H.264 **8-bit** / AAC / MP4 or HLS as the conservative baseline.
- Direct-play validated compatible sources. If only the container is unsupported,
  remux without re-encoding video. Convert unsupported audio separately.
- Transcode unsupported video on Jellyfin/FFmpeg; tone-map HDR to SDR where the
  chosen device/rendition requires it. Server capacity and permissions must be
  verified for the library and concurrent participant count.
- Convert ordinary text subtitles to external WebVTT. Handle image subtitles or
  exact ASS styling through an explicit rendering/burn-in policy; do not silently
  discard them from the downloadable rendition.
- Add device-aware profiles using exact codec/profile/container capability probes
  (`canPlayType`, optionally MediaCapabilities), plus a conservative fallback
  after actual decode failure. Do not treat codec-family support as proof of
  every bit depth/profile/level/HDR combination.
- Prepare compatible downloadable renditions **before** going offline. A cached
  unsupported original cannot ask the server for conversion without networking.

WebCodecs only exposes decoders implemented by that browser/device, and needs
separate demuxing and player machinery. It does not install missing codecs.
Custom WASM decoders can broaden support, but universal full-length playback
while conferencing is not a credible unbenchmarked promise on iPhone.
ffmpeg.wasm's own FAQ reports substantially slower performance than native and
a 2 GB input limit for its documented implementation; these are project limits,
not a universal limit on all possible WebAssembly players.

If the requirement means broad **original-file offline** playback plus robust
background downloads, use a native iOS client with a native transfer service and
broad software/hardware decoder backend. A WKWebView wrapper alone retains web
codec limitations; native bridges/player components are necessary. Even native
players need an explicit supported-format policy rather than literal “any codec”.

## Implementation order and device verification

1. Verify/polish existing standalone watch stage and floating cameras.
2. Correct device-aware playback negotiation and server fallback.
3. Prototype a large compatible MP4 downloaded to OPFS and replayed after restart.
4. Add resumable transfer manager, local library, offline shell and offline entry.
5. Connect local playback to the existing online party synchronization.

Acceptance matrix: minimum supported iPhone OS, current iPhone OS, an older iPhone
and a newer one, and iPad; Safari tab versus Home Screen installation; portrait/
landscape and popup drag/resize; long movies with camera/mic and Bluetooth audio;
lock/background/termination then resume; airplane-mode cold launch and seeking;
low storage; logout/account switch; H.264/AAC, HEVC, AV1, MKV, DTS audio, HDR and
image subtitles. Reconnect must recover room/capture state without stale seeks.

## Sources

- [WebKit: Safari 16.4 features — fullscreen, orientation and WebCodecs](https://webkit.org/blog/13966/webkit-features-in-safari-16-4/)
- [Current MDN data: Element.requestFullscreen](https://github.com/mdn/browser-compat-data/blob/main/api/Element.json)
- [WebKit: OPFS](https://webkit.org/blog/12257/the-file-system-access-api-with-origin-private-file-system/)
- [WebKit: updated storage policy](https://webkit.org/blog/14403/updates-to-storage-policy/)
- [MDN: Background Fetch and service-worker lifecycle constraints](https://developer.mozilla.org/en-US/docs/Web/API/Background_Fetch_API)
- [Current MDN data: BackgroundFetchManager](https://github.com/mdn/browser-compat-data/blob/main/api/BackgroundFetchManager.json)
- [Current MDN data: file picker](https://github.com/mdn/browser-compat-data/blob/main/api/Window.json)
- [Current MDN data: orientation lock](https://github.com/mdn/browser-compat-data/blob/main/api/ScreenOrientation.json)
- [Jellyfin: codec, container and subtitle support](https://jellyfin.org/docs/general/clients/codec-support/)
- [MDN: WebCodecs](https://developer.mozilla.org/en-US/docs/Web/API/WebCodecs_API)
- [ffmpeg.wasm: FAQ and documented limitations](https://ffmpegwasm.netlify.app/docs/faq/)
