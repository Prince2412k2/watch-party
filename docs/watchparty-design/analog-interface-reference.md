# Analog interface reference

Status: foundational interaction sketch supplied by the product owner on 2026-08-05.

The original sketch should be stored beside this document as
`references/12-analog-interface-sketch.png` when the source attachment is
available as a workspace file.

## Product direction

- Replace the existing React and Flutter home/library interfaces rather than
  combining them.
- Give both clients one information architecture and one interaction model.
- Aim for a clean analog feeling: direct, tactile, quiet, and backdrop-led.
- Scrolling and a small set of buttons are the primary controls.
- Preserve the existing media, party, discovery, download, profile, and
  playback contracts behind the new presentation.

## Primary navigation

The main modes remain visible along the bottom edge:

- Home
- Movies
- Shows
- Discover
- Downloads

Home is a curated landing mode, not a second library implementation. It should
compose a small number of high-value shelves from the same canonical media
components used by Movies and Shows.

Home prioritizes:

1. Continue Watching
2. Active or resumable Watch Parties
3. Next Up
4. Recently Added

Profile is a compact control in the upper-right corner. Activating it expands
an inline toolbox rather than opening a separate dashboard or permanent
sidebar.

Watch Party is a compact control in the lower-right corner. Activating it also
expands an inline toolbox. The expanded surface must not cover primary content
or compete with the bottom navigation.

Outside a party, the toolbox offers Create and Join. Once connected, it changes
to room controls with End/Leave, Start Browser, and Show QR Code. Host-only
actions must be visibly distinct from controls available to every participant.

## Browsing model

- The selected media item is the visual anchor.
- Its backdrop fills the stage and changes as selection moves.
- A horizontal strip presents the current collection.
- Poster artwork has square, unrounded edges. This applies to every poster size,
  loading skeleton, placeholder, season card, and selected state in both clients.
  Focus treatment may add an outer frame or shadow, but must not clip or round
  the artwork itself.
- Posters must not read as flat UI tiles. Resting artwork uses restrained
  physical depth: a fine square frame, directional edge light, a tinted cast
  shadow, and slight separation from the backdrop. Selected artwork increases
  elevation and local backdrop shading rather than adding rounded surfaces.
- Selection uses a small forward lift/scale, a stronger directional shadow, a
  brighter edge, and darker local backdrop shading. Avoid perspective tilt and
  playful bounce.
- Poster lighting follows one consistent scene direction. Avoid generic black
  drop shadows, floating card borders, and glow around every item.
- One item always owns a clear default focus position.
- Wheel and trackpad scrolling use stepped focus. Each deliberate gesture moves
  one item; momentum is absorbed so focus never coasts past the intended item.
- Scroll moves focus through items and then into the next collection or level.
- Enter/click activates the focused item.
- A focused collection or franchise opens a second browsing level containing
  its parts.
- The focused item grows or otherwise gains physical emphasis; selection must
  not rely on color alone.
- Controls should feel deterministic. Avoid free-floating carousels, surprise
  auto-rotation, and competing scroll regions.

## Detail model

Activating a movie opens a restrained detail stage:

- Movie backdrop remains the dominant surface.
- Description, title, and essential metadata sit on the left.
- Poster sits on the right.
- Cast runs in a horizontal strip along the bottom.
- A collection title keeps its parts available as a compact strip across the
  top, with the current part visibly selected.
- Back returns to the exact browsing position and focused item.

## Shows

The current Shows view is the behavioral baseline. Preserve its series,
season, and episode navigation while adapting its presentation to the new stage
and focus system.

- Seasons should use their own 2:3 Primary poster whenever Jellyfin supplies it.
- If season artwork is absent or fails to load, use the series Primary poster.
- If series artwork also fails, keep a fixed-size neutral placeholder with the
  season number so layout and focus do not move.
- Selecting a season may promote its poster or backdrop into the stage, but the
  episode list and current selection must remain immediately understandable.
- React and Flutter must derive season artwork from the same Jellyfin season
  item contract rather than maintaining separate metadata-provider behavior.

## Cross-input contract

The same focus model must work with:

- Mouse wheel and trackpad
- Mouse click
- Keyboard arrows, Enter, Escape, and Backspace
- TV/remote directional controls, select, and back
- Touch swipes and taps

Platform-specific input may differ, but focus, activation, back behavior, and
selection persistence must remain equivalent across React and Flutter.

Phones retain the same stage and focus model rather than switching to a
conventional vertical feed. The backdrop remains full-screen, one tactile shelf
owns focus, bottom modes remain available, and swipe/tap map to the same stepped
selection and activation contract used by wheel/keyboard/remote input.

## Guardrails

- No duplicate home experiences.
- No permanent sidebar.
- No dense dashboard composition.
- No nested independent scroll areas on the main stage.
- No hover-only controls.
- No important action hidden behind gesture-only interaction.
- Motion should communicate focus and depth, not decorate every element.
- Reduced-motion mode must preserve all state changes without spatial effects.

## Visual character

Use a quiet tactile interpretation of analog equipment rather than an overt
retro or CRT theme:

- Warm blacks and softly tinted neutrals instead of pure black.
- Fine, low-contrast grain that does not reduce text or artwork clarity.
- Mechanical, weighty focus movement with restrained easing.
- Selection depth created through scale, framing, light, and position.
- Optional subtle interface sound and platform haptics, always user-controllable.
- No decorative scanlines, heavy phosphor glow, fake static, or novelty channel
  switching effects.
