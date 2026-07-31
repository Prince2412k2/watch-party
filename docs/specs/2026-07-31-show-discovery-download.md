# Show discovery — episode-level downloads and a unified show stage

Status: draft (Phase 1 — spec)
Surface: Flutter desktop/mobile app (`flutter_app`), Express server (`app/server/servarr`)

## Problem

The Discover tab's series screen is a stack of grey season rows with `Monitoring` /
`Search` chips. It looks nothing like the Shows tab's cinematic stage, it offers no way
to download a single episode, and a season search reports `Searching…` indefinitely and
then shows no result. A series with episodes 2–6 already downloaded has no path to
episode 1.

## User stories

### US-1 — Download one episode (P1)
As a viewer browsing a series, I pick a single episode and download it, whether or not
the series is already in my library.

*Independent test:* open a series with episodes 2–6 present, download episode 1, and see
it arrive without touching the other episodes.

- **Given** a series shown in Discover, **when** I select an episode and choose Download,
  **then** I am offered the releases for that episode and the one I pick starts
  downloading.
- **Given** an episode that is already downloaded, **when** I look at its card,
  **then** it offers playback rather than a download affordance.

### US-2 — Download a season, or every season (P1)
As a viewer, I download a whole season, or the entire series, in one action.

*Independent test:* from one screen, download season 3 without affecting seasons 1–2,
then download all remaining seasons.

- **Given** a series with 6 seasons, **when** I choose Download on season 3, **then**
  releases for season 3 are offered and my pick starts downloading.
- **Given** the same series, **when** I choose Download all seasons, **then** every
  season not already complete is queued without asking me to pick a release per season.
- **Given** a season with no season-pack release, **when** all-seasons reaches it,
  **then** it falls back to searching that season's episodes individually.

### US-3 — One show screen, two purposes (P1)
As a viewer, the Discover series screen presents the same stage as a library series —
artwork, series copy, season selector, episode row — with Download in place of Watch now.

*Independent test:* screenshot both screens for the same series; the layout, spacing, and
selection behaviour match, and only the primary action differs.

- **Given** a series not in my library, **when** I open it from Discover, **then** I see
  the cinematic stage with the episode row for the selected season.
- **Given** an episode is selected, **when** the selection changes, **then** the stage
  copy (episode title, overview, rating, runtime, air date) and the primary action swap
  to that episode.

### US-4 — Supply my own release (P2)
As a viewer, when the indexers have nothing usable, I supply a `.torrent` file or a
magnet link for the thing I am looking at.

*Independent test:* right-click an episode, paste a magnet, and see it appear in
Downloads attributed to that episode.

- **Given** any episode, season, or the series, **when** I right-click it, **then** a
  menu offers uploading a `.torrent` file and pasting a magnet link.
- **Given** I supply a magnet, **when** it is accepted, **then** the download is
  attributed to the scope I right-clicked.

### US-5 — Seasons under the wheel (P2)
As a viewer, scrolling anywhere on a show screen moves through seasons; scrolling over
the episode row moves through episodes instead.

*Independent test:* wheel over empty stage area — the season changes; wheel over the
episode row — episodes move and the season does not change.

- **Given** a series with 6 seasons, **when** I scroll over the stage, **then** the
  selected season changes by one step per gesture.
- **Given** the pointer is over the episode row, **when** I scroll, **then** only the
  episode selection moves.
- **Given** the selected season changes, **when** season artwork exists, **then** the
  stage art changes with it. (P3)

### US-6 — Honest search state (P1)
As a viewer, a search that finds nothing, fails, or is still running says so.

*Independent test:* trigger a season search against an indexer with no results; the UI
reports "no releases found" rather than spinning forever.

- **Given** I start a search, **when** it returns no releases, **then** I am told none
  were found and the action is offered again.
- **Given** a search fails upstream, **when** the error arrives, **then** the reason is
  shown and the action is offered again.

## Functional requirements

**Episode data**
- FR-001: The server MUST expose episodes for a season of a series that is not in the
  library — number, name, overview, still image, air date, runtime — sourced from TMDB.
- FR-002: The episode endpoint MUST NOT write to Sonarr; browsing MUST NOT add series to
  the library.
- FR-003: The server MUST resolve a TMDB series id from the identifiers Sonarr's lookup
  returns, so a series reached from either tab can list episodes.
- FR-004: For a series already in the library, episode data MUST come from the existing
  library source, and the two shapes MUST be interchangeable to the UI.

**Downloading**
- FR-005: The server MUST expose an interactive release list for a series, a season, and
  a single episode. The season and episode lookups are the two primitives every download
  scope is built from.
- FR-006: The server MUST expose a grab for a chosen series/season/episode release.
- FR-007: The app MUST offer Download at three scopes, each in its own fixed place:
  whole series beside the series title, the selected season in the hero action row
  labelled with that season (`Download S01`), and the selected/hovered episode on its
  thumbnail. Season and episode scope MUST open the release picker for that scope.
- FR-007a: All-seasons MUST run unattended: for each incomplete season, take the best
  season release; where a season has none, fall back to the best release for each of that
  season's missing episodes. It MUST NOT prompt per season.
- FR-007b: All-seasons MUST report, per season, whether it was satisfied by a season
  release, by episode releases, or not at all.
- FR-008: An episode card MUST carry a download affordance when that episode is not
  already downloaded, and MUST NOT when it is.
- FR-009: Choosing a release MUST report acceptance or rejection, and the affordance MUST
  reflect the resulting state (searching → downloading → downloaded → failed).
- FR-010: A right-click on a series, season, or episode MUST offer a `.torrent` upload
  and a magnet-link entry scoped to that target.
- FR-011: Manual and automatic downloads MUST be attributed to the scope they were
  started from, and MUST appear in Downloads.

**The show stage**
- FR-012: Discover and library series MUST render the same stage: backdrop, series copy,
  season selector, and an episode row for the selected season.
- FR-013: The hero action row MUST carry the season-scoped Download for the selected
  season; where the selected episode is playable it MUST also carry Watch now, and where
  it is already downloaded it MUST say so rather than offering to download it again.
- FR-014: Selecting an episode MUST swap the stage copy — `<Series> · S1 E1 · <name>`,
  the episode overview, rating, runtime, air date, resolution — and the episode-scoped
  state shown in the hero row. It MUST NOT change what the season button targets beyond
  the season that episode belongs to.
- FR-015: Episode names MUST be rendered larger than they are today.
- FR-016: A wheel gesture over the stage MUST step the season; over the episode row it
  MUST step the episode and MUST NOT step the season.
- FR-017: When the selected season has its own artwork, the stage art MUST follow the
  season.

**Failure states**
- FR-018: Every search, release lookup, and grab MUST end in a terminal state — results,
  empty, or an error naming the reason — and MUST NOT present an indefinite progress
  state.
- FR-019: A scope with no usable releases MUST still offer the manual `.torrent`/magnet
  path.

## Success criteria

- SC-001: A single episode of a series with no other missing episodes can be downloaded
  in one pass through the UI.
- SC-002: Season and all-seasons downloads are reachable from the same screen, without
  navigating to a separate chooser.
- SC-002a: All-seasons on a series where one season has no season pack still acquires that
  season's episodes, and says which route each season took.
- SC-003: The Discover series screen and the library series screen are the same layout,
  differing only in the primary action.
- SC-004: No search or download action can leave the UI in a progress state with no
  terminal outcome.
- SC-005: Browsing any number of Discover series adds nothing to the Sonarr library.
- SC-006: A wheel gesture over the stage changes exactly one season per gesture, and a
  wheel gesture over the episode row changes no season.
- SC-007: Episode names on the show stage are visibly larger than the current 11px.
- SC-007a: Each of the three download scopes is reachable in one click from the show
  stage, without opening a menu or another screen.
- SC-008: A `.torrent` file and a magnet link can each be submitted for an episode, a
  season, and a series, and the result is visible in Downloads.

## Out of scope

- Movie download flows (Radarr already has an interactive picker and is unchanged).
- The web client's series screens — this is the Flutter app only.
- Quality-profile or root-folder selection beyond what the existing add flow does.
- Subtitle and audio-track handling.
- Retiring the current season-chooser screen if anything else still routes to it.
- Concurrency limits or scheduling of queued grabs.

## Assumptions

- The Discover stage reuses the existing library stage widget, parameterised by data
  source and primary action, rather than being reimplemented. This is what makes SC-003
  verifiable rather than a pixel-matching exercise.
- `TMDB_API_KEY` is configured. Discover already fails without it, so this adds no new
  operational requirement — but it does add a second place that depends on it.
- Sonarr's series lookup carries a TMDB id; where it does not, TMDB's external-id lookup
  resolves one from the TVDB id. If neither resolves, the episode row is absent and the
  season-level actions still work.
- "Already downloaded" for a Discover series means an episode file exists in the library
  for that series/season/episode; a series absent from the library has none.
- All-seasons cascades: season release per season, falling back to per-episode releases
  for any season without a season pack, and it picks automatically rather than opening six
  pickers. Season and episode scope stay interactive.
- Wheel-driven season stepping is one season per gesture with the same debounce the
  poster shelf uses, so a trackpad flick does not skip four seasons.
- The indefinite `Searching…` is a defect with an unproven cause; it will be
  root-caused under systematic-debugging before FR-018 is implemented, not patched by
  adding a timeout.

## Open questions

None — all markers resolved in the Phase 1 interview.
