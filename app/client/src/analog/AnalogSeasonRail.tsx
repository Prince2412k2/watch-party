import { useEffect, useRef } from 'react'
import { AnalogPoster } from './AnalogPoster.tsx'
import { seasonArtworkItem, seasonLabel, type SeasonItem, type SeriesLike } from './showBrowse.ts'
import type { MotionProfile } from './stageLayout.ts'

/**
 * The season axis, on the right rail.
 *
 * Deliberately the same element as the Movies mode slider — `.an-modes`, not a
 * copy of it — because it is the same control: right-aligned text positions,
 * each carrying its own rule that lengthens on selection, the active label a
 * size step larger. That geometry was lifted FROM the old `.library-seasons`
 * rail when Movies got its slider, so pointing Shows back at it closes the loop
 * rather than reintroducing a second implementation of the thing it came from.
 *
 * The selected season's poster sits above the list, resolved through the shared
 * season chain (season Primary -> series Primary -> fixed placeholder) so a
 * season with no art of its own still shows the show's, and a show with none
 * still shows a fixed-size placeholder that does not move the layout.
 *
 * Up/Down drive it from anywhere on the stage and a stepped scroll drives it
 * from outside the rail, but it is still a real list of buttons: an axis
 * reachable only by gesture would hide the one control that says which season
 * you are reading.
 */
export interface AnalogSeasonRailProps {
  seasons: readonly SeasonItem[]
  /** The season being shown — already resolved, never a stale stack value. */
  selectedId: string | null
  /** The series drilled into, for the poster's fallback step. */
  series: SeriesLike | null
  onSelect: (seasonId: string) => void
  motion: MotionProfile
  disabled?: boolean
}

export function AnalogSeasonRail({
  seasons,
  selectedId,
  series,
  onSelect,
  motion,
  disabled = false,
}: AnalogSeasonRailProps) {
  const listRef = useRef<HTMLDivElement>(null)

  // A twelve-season show is taller than the rail, which scrolls inside itself.
  // Stepping the axis past the visible window without this leaves the user
  // pressing Down against a list that appears not to move at all. `nearest`
  // rather than `center`, so a selection already on screen does not jump.
  useEffect(() => {
    if (!selectedId) return
    listRef.current
      ?.querySelector<HTMLElement>('[aria-selected="true"]')
      ?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
  }, [selectedId])

  if (seasons.length === 0) return null

  const selected = seasons.find((season) => season.Id === selectedId) ?? null

  return (
    <div className="an-seasons">
      {selected ? (
        <span className="an-season-art">
          <AnalogPoster item={seasonArtworkItem(selected, series)} focused={false} motion={motion} eager />
        </span>
      ) : null}

      <div ref={listRef} className="an-modes" role="tablist" aria-label="Seasons">
        {seasons.map((season, index) => {
          const active = season.Id === selectedId
          return (
            <button
              key={season.Id}
              type="button"
              role="tab"
              className={active ? 'is-active' : ''}
              aria-selected={active}
              disabled={disabled}
              onClick={() => onSelect(season.Id)}
            >
              <span>{seasonLabel(season, index)}</span>
              {/* Selection is never colour alone: the active position also
                  carries the longer detent rule, which survives a monochrome
                  display. */}
              <i aria-hidden />
            </button>
          )
        })}
      </div>
    </div>
  )
}
