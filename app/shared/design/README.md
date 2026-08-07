# Analog design foundation

Issues #66 and #67 replace the React and Flutter browsing and player interfaces
with **one** design and **one** interaction model. Before this directory existed
there was nothing in the build tying the two clients together, and four
independent token systems had already drifted apart:

| Where | What it defined | Poster radius | Ground colour |
|---|---|---|---|
| `app/client/src/styles.css` `:root` | `--wp-*`, desktop web | `12px` (`.library-poster-art`) | `#0a0a0b` |
| `app/client/src/mobile/theme.ts` | `T`/`R`/`SP`/`TYPE`, React phone | `16px` (`R.md`) | `#0a0a0b` |
| `flutter_app/lib/ui/tokens.dart` | `AppColors`/`AppSpacing`/`AppMotion` | `12px` (`AppSpacing.radius`) | `#101113` |
| `flutter_app/lib/ui/palette.dart` | `WpPalette`, three live themes | — | per-theme |

Every one of them rounds poster artwork and keys its neutrals cool. The analog
references call for the opposite on both counts — square unrounded artwork at
every size, and warm blacks rather than pure black — so this is a replacement,
not a retheme.

## The two canonical files

Everything in here is **data, not code**, and each file is consumed by tests in
**more than one language**. That is the whole point: editing one to match one
client immediately fails the other, the same way `../contracts/` works for the
wire protocol.

| File | Consumed by |
|---|---|
| `analog-tokens.json` | `app/client/src/design/tokenParity.test.ts` (JS)<br>`flutter_app/test/ui/analog_tokens_parity_test.dart` (Dart) |
| `interaction.json` | `app/client/src/analog/interactionParity.test.ts` (JS)<br>`flutter_app/test/analog/interaction_parity_test.dart` (Dart) |

## `analog-tokens.json` — the values

The single place a token value may be edited. `generate.mjs` emits three
checked-in files from it:

```
app/client/src/design/analogTokens.ts     nested `as const` object
app/client/src/design/analog.css          :root { --an-* } custom properties
flutter_app/lib/ui/analog_tokens.dart     abstract final class AnalogColor { … }
```

Regenerate with:

```sh
node app/shared/design/generate.mjs
```

They are checked in so neither client needs a codegen step in its build — which
is exactly what would let them rot. Two tests close that hole from opposite
sides:

- The **JS** test re-runs the generator in memory and byte-compares all three
  outputs. A hand-edit to any generated file, or a JSON change without a
  regenerate, fails there. It is also the only check on the Dart file's bytes,
  since Dart cannot run the Node generator.
- The **Dart** test re-derives the values from the JSON independently and
  compares them to the constants. Byte-compare cannot catch a *consistently
  wrong* transform — a generator emitting `Color(0xF4EFE6A3)` instead of
  `Color(0xA3F4EFE6)` would regenerate identically forever — so the Dart side
  checks the semantics rather than the spelling.

### Key-suffix conventions

The generator infers a value's type from its key, so the JSON stays readable and
the emitters stay small:

| Suffix / shape | JSON | CSS | TypeScript | Dart |
|---|---|---|---|---|
| value starts `#` | `"#0E0C0A"`, `"#F4EFE6A3"` | `#0E0C0A` | `'#0E0C0A'` | `Color(0xFF0E0C0A)` |
| `*Ms` | `170` | `170ms` | `170` | `Duration(milliseconds: 170)` |
| `*Ease` | `[0.22, 0.61, 0.36, 1.0]` | `cubic-bezier(0.22, 0.61, 0.36, 1)` | `[0.22, …]` | `Cubic(0.22, 0.61, 0.36, 1.0)` |
| `*Px` | `14` | `14px` | `14` | `14.0` |
| `*Pct` | `3.5` | `3.5%` | `3.5` | `3.5` |
| `*Deg` | `315` | `315deg` | `315` | `315.0` |
| plain number | `3` | `3` | `3` | `3.0`, or `int` per the generator's small allowlist |

`$about` keys are documentation; they become comments and are never emitted as
values.

Storing easing as **four control points** rather than a CSS string is what makes
"the same motion in both clients" literal: CSS gets `cubic-bezier(a,b,c,d)` and
Flutter gets `Cubic(a,b,c,d)` from the same four numbers, instead of each side
hand-picking a curve that looks about right.

### Assertions the tests make about the values themselves

Beyond parity, a few design decisions are pinned so they cannot be softened
quietly:

- `poster.radiusPx` is `0`, asserted in **both** languages. "Every poster has
  square, unrounded artwork, including skeletons, placeholders, seasons, and
  selected states."
- The neutral ramp is warm: `r >= g >= b` with a real spread, and never pure
  black or pure white.
- Every easing curve keeps its `y` control points inside `0..1` — a value
  outside that range is precisely what produces the elastic overshoot the
  references rule out.
- `hairline.hitPx` stays at or above the 24px touch floor and far exceeds the
  visible line, so "approximately 2px" can never quietly shrink the target.

`radius.chromePx`/`sheetPx`/`pillPx` exist for buttons, sheets and toasts. They
must never be applied to a poster, still, skeleton or placeholder.

## `interaction.json` — the behaviour

Five pieces of logic that both clients must agree on, implemented once per
language and driven from one set of cases:

| Core | TypeScript | Dart |
|---|---|---|
| stepped scroll, focus restoration, season artwork | `app/client/src/analog/browseCore.ts` | `flutter_app/lib/analog/browse_core.dart` |
| toast queue, control auto-hide, chat shortcut | `app/client/src/analog/playerCore.ts` | `flutter_app/lib/analog/player_core.dart` |

All of it is pure — no DOM, no widgets, no timers. Callers own the clock and
pass `atMs`/`nowMs` in, which is also what makes "four seconds" and "three
seconds" testable without waiting in real time.

**`steppedScroll`** — "each deliberate gesture moves one item; momentum is
absorbed so focus never coasts past the intended item." A notched wheel sends a
few large deltas and a trackpad flick sends dozens of small decaying ones, so
raw delta cannot drive focus. Deltas accumulate to a threshold, at most one step
is emitted per event, a cooldown stops a burst discharging as a run of steps,
and the decaying tail after a step is discarded.

**`restoreFocus`** — "Back returns to the exact browsing position and focused
item." The cases that matter are the ones where *exact* no longer exists:
Continue Watching reorders as you watch and Downloads empties. A removed item
holds its index in the shortened shelf; a vanished or emptied shelf falls back
to the first focusable item; a surface with nothing focusable reports `empty`.

**`resolveSeasonArtwork`** — season Primary → series Primary → a fixed-size
neutral placeholder carrying the season number. Fixed-size on purpose: layout
and focus must not move when artwork is missing. `failedIds` records images
already known to 404 so a retry cannot loop.

**`toastQueue`** — chat toasts while the drawer is closed: at most three
stacked, older ones collapsing into a count, each expiring on its own four
second clock. Messages arriving while chat is open are never queued, and opening
chat dismisses what is visible without resurrecting it on close.

**`autoHide`** — controls hide after three seconds without relevant input, and
never while a hold is taken or playback is paused. The hold set is what keeps
the chrome up mid-interaction; without it the menu you just opened vanishes
under your cursor. Releasing a hold grants the full three seconds again rather
than hiding instantly.

**`shouldToggleChat`** — `Ctrl+C` opens chat, but must not fire inside an
editable field or when text is selected. This is not hypothetical: the Flutter
player today matches `keyC` with **no modifier check**
(`flutter_app/lib/player/player_chrome.dart`), so `Ctrl+C` already toggles chat
and swallows copy; React deliberately bails on all modifiers, so `Ctrl+C` does
nothing there. Neither behaviour is what #67 asks for.

The timing constants in `interaction.json` are duplicated from
`analog-tokens.json`, and a test in each language asserts the two agree — so
changing a token cannot silently invalidate the behaviour cases.

## Changing something

Change the JSON, regenerate, then update both ports. The fixture is the middle
step on purpose: it is the thing that fails loudly when one of the two clients
is forgotten.
