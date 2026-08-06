import { BROWSE_MODES, BROWSE_MODE_LABELS, type BrowseMode } from './movieBrowse.ts'

/**
 * Singles ⇄ Collections.
 *
 * "The way we have a slider for seasons in the show screen, on movies tab will
 * have two options — singles and collections." So it is presented the way the
 * season slider is: plain text positions, each carrying its own detent rule, not
 * a pill or a segmented control.
 *
 * The rule belongs to the position rather than travelling between them, because
 * the positions are label-width and "Singles" and "Collections" are not the same
 * width — a single sliding rule would have to be measured at runtime and would
 * be wrong on the first paint and after every font swap.
 *
 * Up/Down drive it from anywhere on the stage and a stepped scroll drives it
 * from outside the rail, but it is still a real pair of buttons: a mode switch
 * reachable only by gesture would be an important action hidden behind one.
 */
export interface AnalogModeSliderProps {
  mode: BrowseMode
  onChange: (mode: BrowseMode) => void
  disabled?: boolean
}

export function AnalogModeSlider({ mode, onChange, disabled = false }: AnalogModeSliderProps) {
  return (
    <div className="an-modes" role="tablist" aria-label="Movie grouping">
      {BROWSE_MODES.map((candidate) => (
        <button
          key={candidate}
          type="button"
          role="tab"
          className={candidate === mode ? 'is-active' : ''}
          aria-selected={candidate === mode}
          disabled={disabled}
          onClick={() => onChange(candidate)}
        >
          <span>{BROWSE_MODE_LABELS[candidate]}</span>
          {/* Selection is never colour alone: the active position also carries
              the detent rule, which survives a monochrome display. */}
          <i aria-hidden />
        </button>
      ))}
    </div>
  )
}
