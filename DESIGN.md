# Watch Party extension design system

Scope: `app/client/extension/`. This describes the v0.6 extension, not the web or
Flutter application's visual system. Product requirements live in `PRODUCT.md`.

## Direction

A private viewing companion: the video leads, communication stays available,
and management controls appear only when needed. The prior always-visible window
layout was explicitly rejected as clunky.

Use familiar buttons, selects, disclosure groups, and forms. Compactness must
come from grouping and progressive disclosure, not from making every label tiny
or burying functionality behind unfamiliar gestures.

## Type

The self-hosted WP Circular Book family carries regular UI text; Bold supplies
semibold weights. System sans-serif is the fallback. Body text is 13px, party
headings 16px, labels 11–12px, chat messages default to the user's 14px setting.
Only invite codes use monospace. Timestamps and counts use tabular numerals.

## Color

`app/client/extension/public/theme.css` is the token authority for React frames
and the popup. `public/overlay.css` supplies matching chrome inside closed shadow
roots. Maintain parity between them when changing a token.

| Role | Dark | Light |
| --- | --- | --- |
| Background | `#10161c` | `#edf1f4` |
| Surface | `#192128` | `#fbfcfd` |
| Raised surface | `#232e37` | `#eef2f5` |
| Hover/pressed surface | `#303e49` | `#dfe7ed` |
| Text | `#edf3f7` | `#1c303e` |
| Secondary text | `#aabac7` | `#526775` |
| Primary action | `#c4edda` | `#245f4a` |
| Action foreground | `#172b22` | `#f2fbf7` |
| Connected | `#a2dbc0` | `#267353` |
| Danger / device off | `#f29d98` | `#a33535` |

System color preference selects the mode. Mint carries actions and unread state;
red is reserved for device-off and departure actions. Do not add decorative glows.

## Shape and spacing

- Panels: 18px radius and a single low-contrast edge.
- Inputs and ordinary buttons: 9–10px radius.
- Quick controls and launchers: circular buttons in a pill-shaped strip.
- Feeds: 14px radius; minimized feed bubbles are circular.
- Base gaps: 6, 8, 12, 16, 18, and 24px. Group related actions closely.
- Panel depth is a soft, offset, blue-tinted shadow, not a halo.

## Overlay arrangement

- A four-button quick strip at bottom-center contains playback, microphone,
  camera, and fullscreen controls.
- Party access sits bottom-right. Party details show the shared title, named
  participant rows, synchronization policy, and invite copying.
- Preferences replace party details in the same frame. Camera/sound, playback,
  and display settings use disclosure groups; the footer remains reachable.
- Closed chat has an icon-only launcher at top-right. The conversation opens
  as a full-height right-side panel with a 12px top/bottom inset and horizontal
  resizing. Its header uses an icon and participant context,
  not a written Chat title. The composer separates writing from attachment tools.
- Feeds float independently. Their drag and resize chrome is hover/focus-only.
- Narrow viewports clamp panels within the viewport; management controls can
  overlay chat temporarily instead of requiring impossible side-by-side columns.

## Idle and notification states

After three seconds without pointer activity, extension chrome fades away. Open
chat and participant feeds persist. Pointer activity inside YouTube or a known
extension iframe restores controls; keyboard interaction also makes controls
available. Visibility changes never remove the shared owner or panel frames.

Closed chat with unread messages is the one persistent launcher exception:
replace the outline conversation icon with a filled notification variant, show
an unread count, and keep it visible while idle. Opening chat clears the count.
Only real incoming messages count; history replay and outgoing messages do not.
An unread message does not wake the other controls.

## Motion and accessibility

Visibility transitions last 180ms; feed chrome uses 140ms fades. Other state
feedback uses 160ms. Reduced-motion preference removes the fade transitions.
Do not add looping notification animation.

Icon-only controls have action labels and hover titles. Use a visible 2px focus
ring, readable placeholders, inline errors, and disabled states. Participant
avatars reuse the shared identity renderer, including saved account profiles.

## Sources and verification

Implementation: `src/App.tsx`, `src/Chat.tsx`, `src/style.css`, `public/theme.css`,
`public/overlay.css`, `public/popup.css`, `public/panels.js`, and `public/content.js`
under the extension directory. Behavioral regressions are covered by extension
tests and isolated two-user Chromium checks. Manual Safari verification remains
separate from this design record.
