# Watchparty UI Design Guide

## Purpose

**Reader:** the next engineer or agent changing the Watchparty interface.

**After reading:** you should be able to extend the UI without reintroducing the old application shell, grid catalog, clipped poster effects, or duplicate Watch Party controls.

This document describes the destination, not the redesign history. The images in this directory are part of the specification.

## Source-of-truth order

When references disagree, use this order:

1. The rules in this guide.
2. `references/04-library-fullscreen-annotated.png` for the library composition.
3. `references/07-show-detail.png` and `references/08-movie-detail.png` for title-detail composition.
4. Images under `implemented/` for the current working result.
5. Images under `regressions/` only as examples of what must not return.

The visual references are directional rather than literal branding instructions. Do not add Netflix branding, window chrome, or a framed application card.

## Design character

The interface is a cinematic streaming library filtered through a calm, modern creative-portfolio sensibility.

- Premium, quiet, mature, and editorial.
- Content and whitespace create hierarchy.
- Edge-to-edge application background; no rounded outer shell.
- Restrained controls and decoration.
- No gradients used as decoration. Artwork scrims and theme washes are allowed for legibility.
- No glassmorphism, noisy glow, dense dashboards, or SaaS-style panels.
- Use weight and spacing before introducing color or effects.

## Typography

Circular XX Web is the only primary UI family. The supplied files are bundled locally.

| Role | Face | Size | Line height | Tracking |
|---|---|---:|---:|---:|
| Major and detail headings | Circular Light 300 | 40–56px | 1.1 | -0.04em |
| Section headings | Circular Light 300 | 34–44px | 1.1 | -0.04em |
| Body copy | Circular Book 400 | 16–18px | 1.75 | normal |
| UI labels | Circular Book 400 | 14–16px | compact | normal |
| Emphasis | Circular Bold 700 | sparingly | — | — |

Keep headings short and text measures constrained. Do not return to extra-bold, oversized 80px hero typography. JetBrains Mono remains acceptable for compact technical metadata such as runtime, resolution, room codes, and episode numbers.

## Themes

The interface always supports three persisted modes:

### Light

- Soft off-white stage, approximately `#f7f7f7`.
- Dark gray text rather than absolute black where possible.
- Artwork is washed back enough to preserve calm contrast.

### Balanced

- Selected artwork is the strongest environmental element.
- Prefer the selected title's backdrop; fall back to its poster.
- Keep the image soft and cinematic rather than using a loud color gradient.

### Dark

- Near-black stage and near-white text.
- Artwork remains visible under a stronger legibility wash.
- Active state comes primarily from brightness and weight.

Theme controls live in the profile menu. They are not a permanent toolbar.

## Desktop shell

- Full viewport, edge to edge.
- No top bar, persistent wordmark, sidebar, search bar, or rounded outer application frame.
- Profile control sits at the top-right.
- The transparent primary navigation is centered along the bottom.
- Navigation destinations remain Movies, Shows, Discover, and Downloads.
- The popcorn control sits at the bottom-right outside playback.
- Shell controls float directly on the theme background; do not add a large nav panel behind them.

## Library and discovery shelves

- Movies and Shows are horizontally scrollable shelves, never responsive poster grids.
- The catalog begins near the left edge with a generous but not centered margin.
- Shelf arrows sit on the right of the shelf heading.
- The first or currently selected poster is subtly larger, not dramatically zoomed.
- Hover may strengthen the shadow but must not translate the poster upward.
- Rail padding must contain poster scale and shadow. No clipped poster tops or hard shadow cutoffs.
- Poster cards show the title centered below the artwork.
- Do not show a `trailer` label.
- Ratings may sit beneath the title.
- Discover has separate Movies and Shows rails and no search field.
- Additional genre shelves are allowed only when they contain meaningful subsets; do not duplicate the full shelf under another heading.

## Movie detail

Use `references/08-movie-detail.png` as the compositional reference, adapted to the current minimal system.

- Fullscreen backdrop with a theme-aware wash.
- Left column: genres, title, synopsis, compact metadata, Watch/Resume, and track selection.
- Right side: primary poster.
- Bottom area: restrained cast strip with circular portraits or initials fallback.
- Keep the bottom navigation and profile access available without covering content.
- The title stays within 40–56px and body copy within a readable 16–18px measure.

## Show detail

Use `references/07-show-detail.png` as the compositional reference.

- Fullscreen series backdrop and series-level title copy.
- Season selector on the right for desktop.
- Selected-season episode rail near the bottom.
- Selecting an episode updates the playback target and episode metadata.
- Initial action is Play first episode when no episode has been selected.
- Mobile may turn the season selector into a horizontal control.

The current local Jellyfin fixture has no shows, so the show reference remains essential for future visual QA.

## Watch Party interaction

Outside playback:

- Bottom-right circular popcorn control opens the expandable Watch Party widget.
- Preserve room creation, join-by-code, QR invitation, approval, participant management, host transfer, and end-party behavior.

Inside desktop playback:

- Right-click anywhere on the player opens the Watch Party menu.
- Shift + right-click preserves the browser's native context menu.
- Do not render a second desktop Watch Party pill over the top-right player controls.

Inside phone playback:

- Keep a visible Watch Party button because touch devices do not have right-click.

Player chrome, including room controls, auto-hides after three seconds of inactivity while playback is active. Modals, join requests, and important notifications must remain usable.

## Functional invariants

Visual work must not remount or bypass correctness-sensitive systems.

Preserve:

- Playback and track selection.
- Host/guest synchronization and collaborative controls.
- Party, socket, LiveKit, QR, and room-management behavior.
- Authentication and profile actions.
- Jellyfin library and image APIs.
- Discover, download, torrent, and Servarr actions.
- Responsive/mobile behavior where components are shared.

## Anti-regression checklist

Before finishing a visual change, confirm:

- [ ] No top bar, sidebar, search bar, or outer application card returned.
- [ ] Catalogs are horizontal shelves rather than poster grids.
- [ ] Posters and shadows are not clipped at rail boundaries.
- [ ] Hover does not cut off the poster top.
- [ ] Card titles are centered and `trailer` is absent.
- [ ] Profile remains top-right.
- [ ] Popcorn control remains bottom-right outside playback.
- [ ] Desktop player has no overlapping or duplicate Watch Party control.
- [ ] All three themes remain readable.
- [ ] Player controls still auto-hide after three seconds.
- [ ] Existing playback, party, and download actions still work.

## Validation

Run these checks after UI work:

```bash
cd app/client
npm run typecheck
npm test
npm run build
```

For the running Docker application:

```bash
docker compose up -d --build --no-deps watchparty
curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:3001/
```

Visually inspect at approximately `1393×709`, then at a narrower viewport. Exercise Light, Balanced, and Dark; poster hover; profile themes; Discover; Downloads; movie detail; Watch Party expansion; desktop player right-click; and mobile player controls.

## Image manifest

### Primary references

- `references/01-original-shell.webp` — earliest cinematic shell direction.
- `references/02-library-source.png` — source streaming-library composition; ignore its sidebar and branding.
- `references/03-library-fullscreen.png` — clean fullscreen library target.
- `references/04-library-fullscreen-annotated.png` — primary annotated library target.
- `references/05-removal-annotations.png` — explicit removals and control-placement notes.
- `references/06-selection-annotations.png` — selected-poster and background behavior.
- `references/07-show-detail.png` — series detail composition.
- `references/08-movie-detail.png` — movie detail composition.
- `references/09-popcorn-control.png` — supplied Watch Party artwork.
- `references/10-typography-layout-a.png` — editorial spacing and 40/60 layout inspiration.
- `references/11-typography-layout-b.png` — typography, text measure, and whitespace inspiration.

### Current implementation captures

These captures document composition and solved regressions. Some Discover/Downloads captures predate the Circular XX typography pass; the written typography rules take precedence.

- `implemented/library-light.png`
- `implemented/library-card-hover.png`
- `implemented/movie-detail-light.png`
- `implemented/movie-detail-dark.png`
- `implemented/discover.png`
- `implemented/downloads.png`

### Regressions, not targets

- `regressions/party-control-overlap.png` — duplicate/overlapping player controls that must not return.
- `regressions/poster-shadow-clipping.png` — clipped hover/shadow and obsolete trailer label.
