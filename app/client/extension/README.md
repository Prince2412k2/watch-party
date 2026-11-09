# Watch Party for YouTube (v0.2)

Uses the existing Watch Party timeline, chat, SQLite session store, and LiveKit
server. Each person watches YouTube directly; Jellyfin media import is not needed.

## Install and remember setup

From `app/client/`, run `npm ci`, `npm run typecheck:extension`,
`npm run test:extension`, then `npm run build:extension`.

The outputs are `extension/dist/` for **Load unpacked**, and
`extension/watchparty-youtube.zip`. Docker builds package the ZIP automatically.
The public `/extension` page and `/api/extension/download` let guests install
without a Watch Party account. Chrome/Edge **133+** is required.

1. Extract the ZIP, open `chrome://extensions` or `edge://extensions`, enable
   Developer mode, and **Load unpacked** the folder containing `manifest.json`.
2. In the toolbar popup, save the required HTTPS **server URL** and your display
   name. HTTP is allowed for localhost/127.0.0.1 development only.
3. The host fills in the optional **admin username/password** once. Guests leave
   them blank. Server URL, name, username, and the reusable admin login are saved
   in trusted extension storage. The password itself is not stored. Admin login
   lasts thirty days, or until revoked; it authenticates the existing Jellyfin
   administrator account and grants external-party access only.
4. Existing v0.1 users should sign into the new admin setup once. Legacy paired
   devices are migrated without silently granting administrator privileges.

## A fresh party code each time

- **Host:** open any YouTube page, choose **Create party & invite code**, and send
  the displayed `XXXX-XXXX-XXXX` code to everyone. Each party generates a new
  code. Ending a party invalidates that code.
- **Guest:** enter the code and display name in the popup or overlay. The server
  creates a party-scoped guest identity, so no account or password is required.
  Valid invites join directly; the room still supports host removal.
- **Navigation:** the host browses YouTube normally. Home, search, channel pages,
  watch pages, and Shorts URLs follow automatically for guests. Selecting a video
  starts the shared timeline. Guests without control follow the canonical page.
- **Control:** in **People**, the host can **Give control** or **Revoke control**
  for each guest. The server enforces those grants for play/pause, seeking,
  playback speed, and page/video selection. Grants survive reloads; explicit
  departure/removal revokes them. A controller's navigation follows for everyone.

## Native-style floating cameras

Each participant has an independent extension-origin camera iframe, using the
owner's existing LiveKit track through a React portal. This creates no extra RTC
participant and does not send camera pixels/streams through the YouTube page.

The native `FloatingTileGeometry` rules are mirrored: 4:3 cameras, 168px default
width, 112px minimum, viewport-only maximum, edge snapping, draggable/resizable
windows, and a 60px collapsed avatar that restores the previous size. Layouts
are saved locally. Large groups use an overflow camera rail rather than piling
windows onto one position. Cameras remain independent when the chat panel hides.

The popup has separate Join/Setup views with remembered admin status. The room
uses the app's reel branding and bundled Circular font, current-video artwork,
one-click invite copying with confirmation, clear camera/mic states, unread chat
badges, participant role labels, and keyboard-visible focus throughout.
The room uses comfortable text sizes and an expandable Invite card; copying a
code closes that card after confirmation to leave more space for chat. Guests
see their saved server before joining, and host controls live in the People tab.

Fullscreen atomically moves both overlay layers into the fullscreen subtree,
preserving iframe state. After a full page reload, the same tab rejoins its room
and restores camera/mic choices for that party. Programmatic page following gets a
short reconnect grace period; ordinary host disconnection still pauses the room.

## Settings and scope

Shared controls include 0.25×–2× speed and Lead/Follow buffering modes. Personal
controls include camera/mic/speaker devices, per-person voice volume, hidden/self
feeds, default tile width, sync tolerance/correction, chat size, and panel docking
and opacity. YouTube captions, quality, and video volume stay personal.

Use one active party tab per account. Regular on-demand videos and YouTube page
navigation are targeted; synchronized live streams, mobile YouTube, Firefox, and
other providers are not implemented. Ads are not skipped: host ads freeze the
content timeline; guest ads hold the group in Follow mode only.

LiveKit uses the deployment's existing public signaling URL and TURN settings.
The backend and extension version must be upgraded together.

## Verification

- From `app/`: `node --test server/extension.integration.test.js` covers optional
  admin login, account-free invites, host-only room creation, guest scoping,
  individual control grants/revocation, navigation, fresh/expired party codes,
  chat, speed, buffering, LiveKit grants, and token revocation.
- `test:extension` checks correction math and the actual content/floating scripts
  in a simulated DOM, including origin boundaries and native-style tile geometry.
- Two-profile Chromium smoke testing uses a local YouTube-shaped fixture,
  synthetic devices, and real isolated LiveKit. A live-YouTube manual pass still
  covers site-specific navigation, ad inventory, and browser permission prompts.
