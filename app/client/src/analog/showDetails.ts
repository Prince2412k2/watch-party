// What the Shows stage says about the item under the cursor.
//
// The meta line, the eyebrow and the enrichment rule are movieDetails.ts
// verbatim — a runtime is a runtime and a resolution is a resolution — so only
// the two derivations that genuinely differ live here: how an item names itself
// (an episode is "Sherlock · S2 · E3", a movie is just its title) and what the
// primary action does (a series OPENS, because its episodes are the story its
// own details are not).
//
// Pure, so the failures that actually happen — a Resume label on a series that
// cannot play, an episode code rendered from a missing season number, a
// download button offered for a container — are testable without a DOM.

import { fmtRuntimeFromTicks } from '../lib/format.ts'
import { resumeTicks, type StageActions, type StageItem } from './movieDetails.ts'
import { SERIES_TYPE, EPISODE_TYPE } from './showBrowse.ts'

/**
 * A Jellyfin item as this stage's rails deliver it.
 *
 * `ParentIndexNumber` is the season number an episode belongs to and
 * `SeriesName` its show; neither is meaningful on a movie, which is why they
 * extend `StageItem` here instead of widening it for every surface.
 */
export interface ShowStageItem extends StageItem {
  ParentIndexNumber?: number | null
  SeriesName?: string | null
}

/**
 * The episode code, or null when the numbers are not there to build one.
 *
 * A season number of 0 is Specials, which is a real season — so this tests for
 * null rather than falsiness, or every special would render as a bare "E4".
 */
export function episodeCode(item: ShowStageItem): string | null {
  const season = item.ParentIndexNumber
  const episode = item.IndexNumber
  if (season != null && episode != null) return `S${season} · E${episode}`
  if (episode != null) return `E${episode}`
  if (season != null) return `S${season}`
  return null
}

/**
 * The leading part of the eyebrow: where this item sits.
 *
 * An episode says which show and which slot in it — the title on the stage is
 * the EPISODE's name, so without this the screen never says what you are
 * watching. A series says how big it is. `seriesName` is the fallback for the
 * episode payloads that carry `SeriesId` but not `SeriesName`.
 */
export function showContext(
  item: ShowStageItem | null,
  seriesName?: string | null,
): string | null {
  if (!item) return null

  if (item.Type === SERIES_TYPE) {
    const seasons = item.ChildCount ?? 0
    return seasons > 0 ? `${seasons} season${seasons === 1 ? '' : 's'}` : null
  }

  if (item.Type !== EPISODE_TYPE) return null
  const parts = [item.SeriesName ?? seriesName ?? null, episodeCode(item)].filter(
    (part): part is string => Boolean(part),
  )
  return parts.length > 0 ? parts.join(' · ') : null
}

/**
 * The primary action's label.
 *
 * A series is the one item on this stage that does not play. Everything else is
 * an episode, and an episode resumes from `UserData.PlaybackPositionTicks` the
 * same way a movie does — that is the whole point of the two surfaces sharing a
 * model.
 */
export function showPlayLabel(item: ShowStageItem | null): string {
  if (!item) return 'Play'
  if (item.Type === SERIES_TYPE) {
    const seasons = item.ChildCount ?? 0
    return seasons > 0 ? `Open ${seasons} season${seasons === 1 ? '' : 's'}` : 'Open series'
  }
  const resume = resumeTicks(item)
  const label = resume ? fmtRuntimeFromTicks(resume) : null
  return label ? `Resume ${label}` : 'Play'
}

/**
 * Which actions the stage offers for the focused item.
 *
 * `native` is `IS_NATIVE`: a browser tab has nowhere to put a downloaded file,
 * and rendering the control disabled everywhere else would leave a permanently
 * dead button on a primary surface. Audio/subtitle selection is gated the same
 * way it is on Movies — on there being a media file behind the item at all.
 */
export function showActions(item: ShowStageItem | null, native: boolean): StageActions {
  if (!item) return { plays: false, label: 'Play', tracks: false, download: false }
  const playable = item.Type !== SERIES_TYPE
  return {
    plays: playable,
    label: showPlayLabel(item),
    tracks: playable,
    download: playable && native,
  }
}
