import { useState } from 'react'
import { AnIcon } from '../icons.tsx'
import { DiscoverSheet, SheetNotice } from './DiscoverSheet.tsx'
import type { CatalogItem, Kind } from './catalog.ts'
import type { MotionProfile } from '../stageLayout.ts'

/**
 * Removing a title deletes its files and stops it being fetched again, so it
 * gets a confirmation rather than a second tap on the same button.
 *
 * The destructive action is NOT the default: the sheet opens with nothing
 * focused into it beyond the panel, and Cancel is the one that reads as safe.
 */
export interface RemoveSheetProps {
  item: CatalogItem
  kind: Kind
  motion: MotionProfile
  onClose: () => void
  onConfirm: () => Promise<void>
}

export function RemoveSheet({ item, kind, motion, onClose, onConfirm }: RemoveSheetProps) {
  const [removing, setRemoving] = useState(false)
  const [error, setError] = useState('')

  const confirm = async () => {
    setRemoving(true)
    setError('')
    try {
      await onConfirm()
    } catch {
      setError('Couldn’t remove this title. Please try again.')
      setRemoving(false)
    }
  }

  return (
    <DiscoverSheet
      eyebrow="Remove"
      title={item.title}
      subtitle={item.year != null ? String(item.year) : null}
      item={item}
      motion={motion}
      onClose={onClose}
      busy={removing}
      footer={
        <div className="an-drecovery">
          <button type="button" className="an-action" disabled={removing} onClick={onClose}>
            <span>Keep it</span>
          </button>
          <button type="button" className="an-action is-danger" disabled={removing} onClick={() => void confirm()}>
            <AnIcon name="trash" size={15} />
            <span>{removing ? 'Removing…' : 'Remove and delete files'}</span>
          </button>
        </div>
      }
    >
      <p className="an-dempty">
        This deletes the {kind === 'movie' ? 'movie' : 'series'} and its downloaded files, and stops it being
        fetched again. It can’t be undone.
      </p>
      {error ? <SheetNotice tone="error">{error}</SheetNotice> : null}
    </DiscoverSheet>
  )
}
