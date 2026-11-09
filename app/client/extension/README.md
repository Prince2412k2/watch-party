# Watch Party for YouTube (v0.4)

Uses the existing Watch Party timeline, chat, SQLite session store, and LiveKit
server. Each person watches YouTube directly; Jellyfin media import is not needed.

## Install and remember setup

From `app/client/`, run `npm ci`, `npm run typecheck:extension`,
`npm run test:extension`, then `npm run build:extension`.

The outputs are `extension/dist/` for **Load unpacked**, and
`extension/watchparty-youtube.zip`. Docker builds package the ZIP automatically.
The public `/extension` page and `/api/extension/download` let guests install
without a Watch Party account. Chrome/Edge **133+** is required.

### macOS Safari test build

Safari requires conversion of the unpacked extension into a Safari Web Extension
using Xcode's `safari-web-extension-converter`; it cannot install the ZIP directly.
Rebuild your converted app with the updated extension files, enable it in Safari,
grant access to YouTube and your server, then reload the YouTube tab.

Version 0.3.1 guards Chrome's optional `storage.local.setAccessLevel` API so its
absence does not crash Safari's background worker. Browsers without
`storage.session` use namespaced local extension storage for navigation and
camera/mic preferences. Request timeouts use `AbortController`; Settings opens in
an extension tab when the browser cannot open the toolbar popup programmatically.
The backend CORS handler also accepts Safari Web Extension UUID origins; deploy
that server change for cross-origin requests from Safari's embedded panels.
Compatibility regressions are covered by automated tests; a macOS Safari
end-to-end pass remains necessary.

### Chrome / Edge

1. Extract the ZIP, open `chrome://extensions` or `edge://extensions`, enable
   Developer mode, and **Load unpacked** the folder containing `manifest.json`.
2. Enter a code and click **Join**. The default server is
   `https://watch.sniffkin.tech`; guests need no configuration or account. A guest
   name is generated automatically. **Settings** lets you change the server/name;
   custom servers require HTTPS (HTTP is limited to localhost/127.0.0.1).
3. The host fills in the optional **admin username/password** and uses **Validate & save**. Guests leave
   them blank. Server URL, name, username, and the reusable admin login are saved
   in trusted extension storage. The password itself is not stored. Admin login
   lasts thirty days, or until revoked; it authenticates the existing Jellyfin
   administrator account and grants external-party access only.
   Invalid credentials or an unreachable server leave the saved settings unchanged.
4. Existing v0.1 users should sign into the new admin setup once. Legacy paired
   devices are migrated without silently granting administrator privileges.

## A fresh party code each time

- **Host:** click **Create code** in the popup or YouTube panel, and send
  the displayed `XXXX-XXXX-XXXX` code to everyone. Each party generates a new
  code. Ending a party invalidates that code.
- **Guest:** enter the code in the popup or panel and click **Join**. The server
  creates a party-scoped guest identity, so no account or password is required.
  Valid invites join directly; the room still supports host removal.
  Admins can also join with a code while retaining their validated admin login.
- **Navigation:** the host browses YouTube normally. Home, search, channel pages,
  watch pages, and Shorts URLs follow automatically for guests. Selecting a video
  starts the shared timeline. Guests without control follow the canonical page.
- **Control:** click a person's avatar to **Give control** or **Revoke control**
  for each guest. The server enforces those grants for play/pause, seeking,
  playback speed, and page/video selection. Grants survive reloads; explicit
  departure/removal revokes them. A controller's navigation follows for everyone.

## Native player design and independent panels

The extension mirrors `flutter_app/lib/ui/palette.dart`, `tokens.dart`, and
`party/party_controls.dart`: charcoal `#101113` / `#17181b` surfaces, off-white
`#f2f1ed` primary controls, Circular Light headings and Book labels, hairlines,
and compact monochrome icon trays. Red is reserved for the brand and semantic
danger/off-device states. Participant avatars replace the old roster/tab layout.

Party, Chat, and Camera & mic are separate draggable/resizable windows. Hide and
reopen Chat/Camera & mic from the Party tray. Their extension-origin frames use
React portals into the owner's existing tree: they create no extra Socket.IO
or LiveKit connections. Chat messages align like the native chat panel, with
your messages on the right. Device selection is behind **Devices** in the A/V
panel. The collapsed 44px launcher is draggable; dragging does not open it.

### Floating cameras

Each participant has an independent extension-origin camera iframe, using the
owner's existing LiveKit track through a React portal. This creates no extra RTC
participant and does not send camera pixels/streams through the YouTube page.

The native `FloatingTileGeometry` rules are mirrored: 4:3 cameras, 168px default
width, 112px minimum, viewport-only maximum, edge snapping, draggable/resizable
windows, and a 60px collapsed avatar that restores the previous size. Layouts
are saved locally. Large groups use an overflow camera rail rather than piling
windows onto one position. Cameras remain independent when the chat panel hides.

The popup shows connection status, a code field and Join for everyone, and
Create code for verified admins. Setup fields are only in Settings. The panel
uses the same minimal pre-party controls. Host controls live on participant faces.

## Startup and popup lifecycle

The MV3 module worker owns validation and create/join requests. Those actions
survive popup closure, and write the active tab/party before handing off to its
panel. The panel acknowledges joining before the worker releases its temporary
socket, avoiding host-disconnect races. Existing YouTube tabs receive an open
message; tabs with an old content script are reloaded during handoff.

Only the assigned party tab opens a persistent room/RTC connection. Other
YouTube tabs stay unconnected. Create/join from another YouTube tab transfers
ownership and disconnects the previous tab; from another website it reuses the
existing party tab. Ownership updates and departures are serialized by the worker.

The popup's **Disconnect** button ends the party for a host or leaves for a guest.
Closing the assigned tab does the same: the host's code is invalidated, active
party/code and follow/AV cache are cleared, and guest credentials are discarded.
Saved setup and validated admin login remain. Closing an unrelated tab has no
effect. The open popup observes cleanup and hides its code immediately. If the
server is unreachable, local cleanup still happens; the worker retains a pending
server departure and retries on its next startup/create/join. Normal server
disconnect grace remains the fallback while offline.

Page following uses a trusted background `tabs.update` RPC, rather than asking
Safari's embedded iframe to navigate its parent. It retries while joined,
checks the assigned tab/party, and stops after disconnect. Reloads and full page
navigation preserve the party; closing the tab ends/leaves it.

Embedded panels use a trusted runtime storage broker rather than reading
iframe storage directly. Startup has a five-second deadline and a Retry action;
optional navigation cache reads cannot block it. The broker rejects content
script callers. `/api/extension/me` verifies the saved admin role instead of
relying solely on a cached flag.

After updating, reload the extension **and the YouTube tab**. Version 0.3+ needs
the updated backend endpoints (`health` and `me`) deployed with the new ZIP.

On browsers supporting `moveBefore`, fullscreen atomically moves both overlay
layers into the fullscreen subtree, preserving iframe state. Older browsers use
a normal DOM move and may reload their frames. After a full page reload, the same tab rejoins its room
and restores camera/mic choices for that party. Programmatic page following gets a
short reconnect grace period; ordinary host disconnection still pauses the room.

## Settings and scope

Shared controls include 0.25×–2× speed and Lead/Follow buffering modes. Personal
controls include camera/mic/speaker devices, per-person voice volume, hidden/self
feeds, default tile width, sync tolerance/correction, chat size, and panel docking
and opacity. YouTube captions, quality, and video volume stay personal.

One active party tab is enforced per extension profile. Regular on-demand videos and YouTube page
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
  in a simulated DOM, including origin boundaries, native-style tile geometry,
  independent panel hiding, launcher dragging, default server joining, Safari
  API fallbacks, tab-scoped navigation, and tab-close cache cleanup.
- Two-profile Chromium smoke testing uses a local YouTube-shaped fixture,
  synthetic devices, and real isolated LiveKit. Version 0.4 additionally verifies
  native palette, chat/AV portals, fullscreen state, collapsed launcher dragging,
  automatic following, single-tab transfers, host and guest tab closure, host and
  guest Disconnect, code invalidation, and retained admin login. A live-YouTube manual pass still
  covers site-specific navigation, ad inventory, and browser permission prompts.
