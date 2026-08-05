# Player interface reference

Status: foundational player interaction sketch supplied by the product owner on
2026-08-05.

The original sketch should be stored beside this document as
`references/13-player-interface-sketch.png` when the source attachment is
available as a workspace file.

This reference extends `analog-interface-reference.md`. The React and Flutter
players should expose the same hierarchy and behavior even when their native
media implementations differ.

## Default player

Video owns the full stage. Controls appear over it without a permanent chrome
or separate control panel.

The bottom transport contains:

- Play/pause at the lower-left.
- A full-width seek track directly above the button row.
- Subtitle control near the lower-right as a direct action.
- Mute/unmute.
- Settings.
- Fullscreen at the far lower-right.

Volume is adjusted with a compact vertical control near the right edge rather
than a long horizontal slider in the bottom transport.

### Timeline and volume treatment

The timeline and vertical volume track are thin precision lines, not filled
bars. Minimal geometry must not remove information or reduce the hit target.

- Keep the visible idle line approximately 2px thick while providing a much
  larger invisible pointer/touch target.
- During hover, focus, or scrubbing, the visible line expands slightly to about
  4px without moving surrounding controls.
- Played progress is the strongest line segment.
- Loaded/buffered ranges use quieter tonal segments behind played progress,
  including visible gaps when the playback engine exposes separate ranges.
- Unloaded duration remains a low-contrast hairline.
- Cached/offline spans remain distinguishable from transient network buffer
  when both are available.
- The scrub handle is small and appears on hover, focus, or active scrubbing;
  keyboard/remote focus must remain obvious without permanently enlarging it.
- Hover, focus, and drag retain the time label and trickplay preview.
- Current time and duration remain available without making large labels part
  of the resting chrome.
- Buffering, quality switching, and sync catch-up retain distinct feedback.
- The volume track follows the same hairline treatment and preserves mute,
  previous-volume restore, keyboard adjustment, and a sufficiently large touch
  target.

Party media controls sit along the left edge:

- Microphone.
- Camera.
- Participant/self-view visibility control, pending final confirmation.

Participant video appears as a movable tile over the video. The tile must not
round or soften the underlying video image unless the final visual system calls
for a separate physical frame around it.

## Chat and party layout

A compact control near the upper-right opens and closes chat. `Ctrl+C` toggles
the same surface. The shortcut must not fire while focus is inside an editable
text field and must not override the platform copy command when text is
selected.

Chat opens as a right-side drawer. The movie stage yields enough horizontal
space for the drawer rather than being covered by it. Docked participant tiles
remain visible in a grid immediately beside the drawer.

Participant layout remains directly manipulable without a separate editing
mode:

- Participant tiles can be moved between floating positions and an ordered
  grid/dock.
- Moving a tile into the dock snaps it into a visible slot. Docked tiles can be
  reordered rather than freely overlapping.
- A strong but restrained placement preview shows the destination before drop.
- The movie remains visible and playable while arranging participants.
- The active drag target and keyboard focus must be perceivable without relying
  on color alone.
- Layout actions must have keyboard/remote alternatives to pointer dragging.
- Layout state should remain stable when player controls auto-hide.

### Chat notifications

New messages can appear over the player as compact semi-transparent toasts.
They disappear without requiring dismissal and must not cover subtitles,
transport controls, participant faces, or the chat toggle.

- Toasts appear only while the chat drawer is closed.
- Each toast remains for four seconds unless chat is opened first.
- Up to three messages stack at once. Additional older messages collapse into
  a count rather than extending across the player.
- Toasts identify the sender and show a short message preview.
- Opening chat dismisses visible message toasts and exposes the full messages.
- Notifications are announced accessibly without moving keyboard focus.
- Reduced-transparency mode uses an opaque surface with equivalent contrast.
- Message content must not remain visible on a locked or backgrounded device.

## Settings

Activating the gear expands a compact vertical stack upward from the lower-right
control area. It does not open a full-screen modal.

The stack groups:

- Subtitle settings.
- Language/audio track.
- Playback speed.
- Additional player settings that earn a place through actual use.

The direct subtitle button remains outside this menu for fast track selection
and Off. Subtitle settings contain styling controls such as size, position,
color, delay, and background treatment.

## Interaction character

- Controls should feel mechanical and direct, consistent with the quiet analog
  direction.
- Use short, weighty movement and clear detents rather than elastic or playful
  animation.
- Keep the control count low and reveal secondary controls progressively.
- Controls must be operable by mouse, keyboard, remote, touch, and accessibility
  actions.
- Auto-hidden controls must return on pointer movement, tap, focus movement, or
  a relevant media key without changing playback state.
- During playback, controls hide after three seconds without relevant input.
- On narrow phone screens, one participant tile is visible at a time and a
  horizontal swipe moves between participants.
- Reduced-motion mode removes spatial transitions while preserving placement
  previews and state feedback.

## Functional preservation

The new visual system must preserve existing player behavior rather than
reducing the player to the controls shown in the sketch:

- Played position, duration, loaded/buffered indication, scrubbing, and
  controller/guest permission state.
- Trickplay thumbnails and seek-time previews where artwork is available.
- Local volume and mute for every participant, independent of playback control.
- Subtitle Off/track selection, external subtitle loading, and subtitle styling.
- Audio-track selection and platform-appropriate quality or decoder controls.
- Fullscreen and phone-safe immersive mode.
- Playback loading, errors, retry, sync catch-up, and quality-switch feedback.
- Existing keyboard, remote, touch, and double-tap seek behavior.
- Microphone, camera, participant layout, chat, and party-management behavior.

React and Flutter may expose different engine capabilities, but they should use
the same control hierarchy and must not silently drop a capability during the
redesign.
