# Native player and PWA parity

The Flutter macOS player is the reference. The web player uses the same arrangement and interactions at desktop and phone sizes, with touch targets enlarged to 44px. Native source was inspected; this change has not been visually verified on a physical Mac and iPhone side by side.

| Area | Native reference | Web/PWA implementation |
| --- | --- | --- |
| Top row | `player/player_chrome.dart`: circular Back + title, chat at the right | Back minimizes; title truncates before chat |
| Device controls | `party/party_controls.dart`: left centered mic, camera, self-view rail | Same order and placement; hiding self does not stop publishing |
| Playback | `player/player_chrome.dart`: timeline above transport; play/time left, captions/settings right | Same arrangement; controls hide after 3 seconds during playback, remain during scrubbing/menus |
| Movie window | `player/player_host.dart`: persistent player above routing | Back/Escape minimizes; browsing preserves the video, source and room; drag snaps to corners, bottom-right resize, tap expands |
| Close movie | `player/player_host.dart`: close solo playback or return a party to the lobby | Stop watching keeps the party and call alive; ending the party is a separate confirmed action |
| Cameras | `ui/widgets/floating_camera_tile.dart`: independent 4:3 tiles, default 168px, collapsed 60px avatars | Drag, edge snap, resize, collapse and local controls; stack upwards from bottom-right, scroll when crowded; room audio survives hidden/off cameras |
| Party | `ui/widgets/popcorn_control.dart`: popcorn tray + compact management panel | End/leave, copy invite, roster, transfer/remove, Follow/Lead sync modes, reconnect, viewer pointers; guests retain the existing collaborative-control option |
| Chat | `party/party_overlay.dart`, `ui/widgets/chat_panel.dart`: opaque right card, 360ms open/240ms close | Overlays without resizing the movie; autofocus composer, restore focus on close, own messages right, send failures retain draft, Ctrl/Cmd+C respects selected text |
| Notifications | Native toast queue above camera layer | One room-owned queue across movie, floating and lobby; incoming chat never opens the drawer |
| Keyboard | Native player and party shortcuts | Space/K, arrows/J/L, M, Ctrl/Cmd+C, T push-to-talk, Escape; movie shortcuts are disabled while browsing with a floating movie |

Paths above are relative to `flutter_app/lib/`.

## Requested platform differences

- iOS does not expose system brightness or hardware volume to a PWA. Brightness controls are removed from web; phone/tablet volume sliders are removed. Movie mute remains; desktop web retains media volume.
- The PWA has no fullscreen button, as requested. A tap toggles controls without dimming the movie.
- Phone floating-window buttons are 44px rather than the native desktop's 26px header. Portrait chat leaves room for collapsed cameras.
- The floating window stays within the PWA. A website cannot reproduce a native always-on-top window outside the app.
- iOS camera/microphone permission prompts and capture indicators remain controlled by the operating system.

## Verification

Run the client tests, typecheck and production build, plus the server tests. `scripts/pwa-playback-smoke.mjs` checks active-download seeking and phone bounds.

`scripts/pwa-native-parity-smoke.mjs` starts an isolated app and Jellyfin fixture, then connects two real browser clients through a local LiveKit dev server. It verifies source/element stability across camera sharing and minimize/browse/expand, chat sizing/focus, camera-off audio, collapse/self-hide, push-to-talk, reconnect, guest leave and stopping a movie without stopping the camera. Run with `WP_PARTIAL=1` to repeat with an incomplete download. Setup instructions are at the top of each script.

Before claiming pixel parity, compare the native app and installed iPhone PWA on-device: portrait/landscape, notch/home-indicator bounds, opening the keyboard in chat, system permission prompts, safe-area changes after resume, and dragging/resizing multiple camera tiles. The root `100vh` and opaque status-bar fix also needs confirmation on the affected iOS version; Chromium cannot reproduce that WebKit issue.
