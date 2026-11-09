# Watch Party for YouTube

Chrome/Edge Manifest V3 extension for the existing Watch Party backend. Each
viewer watches YouTube directly; the server coordinates the timeline, chat,
membership, and LiveKit camera/microphone room. No Jellyfin media import is used.

## Build and install

From `app/client/`:

```sh
npm ci
npm run typecheck:extension
npm run test:extension
npm run build:extension
```

This produces `extension/dist/` (load-unpacked directory) and
`extension/watchparty-youtube.zip`. Production Docker builds include the ZIP;
signed-in users can download it at **Profile → YouTube extension**, or
`/extension`. The backend changes and new web client must be deployed together.

1. Use Chrome or Edge **133+**. Extract the ZIP, open `chrome://extensions` or
   `edge://extensions`, enable Developer mode, and **Load unpacked** the folder
   containing `manifest.json`. Alternatively, load `extension/dist/` directly.
2. Open the extension toolbar popup, enter your HTTPS Watch Party server origin,
   and grant access to that server. HTTP is supported only for `localhost` or
   `127.0.0.1` development. No server-specific manifest edit is needed.
3. Open the pairing page from the popup. Sign into Watch Party, generate a
   one-use code, and paste it into the popup. Codes expire after five minutes;
   pairings expire after thirty days and can be revoked on `/extension`.
4. Reload an already-open YouTube tab. Open a regular `www.youtube.com/watch?v=…`
   video and click **Watch Party** in the lower corner. Start a room or enter a
   friend's eight-character room code. The host approves first-time guests.
5. Enable camera/microphone explicitly and grant browser permission. Use one
   active YouTube party tab per account. Reloads and video navigation in that
   tab rejoin the room; unrelated YouTube tabs do not automatically join it.

Use the backend's normal LiveKit public signaling and TURN configuration. The
extension uses the same authenticated room-token proxy, so private container
hostnames must not be advertised as `LIVEKIT_PUBLIC_URL`.

## Controls

- Native YouTube play/pause, seek, keyboard shortcuts, and speed changes author
  shared commands when you have control. Guests otherwise follow the room.
- The host can enable **Everyone can control**, choose **Lead** (guests catch
  up) or **Follow** (buffering pauses everyone), approve/decline/remove viewers,
  transfer hosting, or end the party. Guests can leave independently.
- Shared speed: 0.25×–2×. Quality, captions, local volume, and YouTube account
  preferences remain personal. Changing the room video is an explicit action:
  the controller opens a different video and clicks **Watch this video instead**.
- Personal options: gentle speed correction or strict seeks, drift tolerance,
  auto-follow video changes, camera/mic/speaker devices, default and per-person
  voice volume, own-tile visibility, camera tile size, hidden feeds, chat text
  size, dock side, and opacity. Settings persist in extension-local storage.
- Drag the overlay's top bar to move it; resize with the lower corner. **Hide**
  collapses it without leaving. YouTube fullscreen keeps the overlay, chat, and
  cameras; Chrome's atomic DOM move avoids reloading the extension iframe.

## Current scope and verification

- Regular on-demand YouTube videos only. Live streams, Shorts, mobile YouTube,
  Firefox, and other providers are not implemented.
- Ad detection suspends local corrections. A host ad freezes the content
  timeline even in Lead; guest ads hold everyone only in Follow. This does not
  skip/block ads. Different ad inventories can still cause a catch-up afterward.
- If autoplay is blocked, click Play on YouTube once. If room audio is blocked,
  click **Enable room audio**. Speaker selection depends on browser support.
- This extension bundles its code locally; it does not load remote scripts.
  The isolated content script sees player state and media commands, not the
  pairing credential. Pairings grant external parties and room tokens only,
  not Jellyfin HTTP API access. Tokens are hashed in the server's SQLite store.
- Backend integration test: from `app/`,
  `node --test server/extension.integration.test.js`. It starts an isolated
  test-mode backend and covers pairing, membership/approval, chat, authority,
  speed, ads/buffering, media generations, LiveKit grants, and revocation.
- `test:extension` covers timeline math and the actual content script in a
  simulated DOM, including input intent, loop suppression, ads, origin/source
  checks, and fullscreen placement. A two-profile Chromium smoke pass also
  exercised the loaded extension with a local YouTube-shaped video fixture,
  synthetic camera/microphone, and a real isolated LiveKit server: approval,
  chat, synchronized playback, remote A/V, fullscreen without disconnecting,
  speed changes, and same-tab reload recovery passed. A manual live-YouTube
  pass remains necessary for real site, ad inventory, and permission prompts.
