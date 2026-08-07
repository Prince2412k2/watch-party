import { useEffect, useState } from 'react'
import { AnIcon } from '../icons.tsx'
import { apiJson } from '../../types/guards.ts'
import { jpost } from '../../lib/api.ts'
import { DiscoverSheet, SheetField, SheetNotice } from './DiscoverSheet.tsx'
import {
  outcomeOf,
  requestBody,
  serviceFor,
  type CatalogItem,
  type CatalogMetadata,
  type Kind,
} from './catalog.ts'
import { outcomeToState, type RequestState } from './cardState.ts'
import type { MotionProfile } from '../stageLayout.ts'

/**
 * The same request as the one-tap Download, with its defaults exposed.
 *
 * Quality profile and root folder for both kinds; a language profile and the
 * monitor/search toggles for series only, because a movie request is a single
 * deterministic grab-or-remove and has nothing to keep monitoring.
 */
export interface OptionsSheetProps {
  item: CatalogItem
  kind: Kind
  motion: MotionProfile
  loadMeta: () => Promise<CatalogMetadata>
  onClose: () => void
  onSettled: (state: RequestState) => void
}

interface Outcome {
  tone: 'ok' | 'warn' | 'error'
  message: string
}

export function OptionsSheet({ item, kind, motion, loadMeta, onClose, onSettled }: OptionsSheetProps) {
  const service = serviceFor(kind)
  const [meta, setMeta] = useState<CatalogMetadata | null>(null)
  const [load, setLoad] = useState<{ loading: boolean; error: string }>({ loading: true, error: '' })

  const [qualityProfileId, setQualityProfileId] = useState<number | null>(null)
  const [rootFolderPath, setRootFolderPath] = useState<string | null>(null)
  const [languageProfileId, setLanguageProfileId] = useState<number | null>(null)
  const [monitor, setMonitor] = useState(true)
  const [searchNow, setSearchNow] = useState(true)

  const [submitting, setSubmitting] = useState(false)
  const [outcome, setOutcome] = useState<Outcome | null>(null)

  useEffect(() => {
    let cancelled = false
    setLoad({ loading: true, error: '' })
    loadMeta()
      .then((value) => {
        if (cancelled) return
        setMeta(value)
        setQualityProfileId(value.profiles[0]?.id ?? null)
        setRootFolderPath(value.rootFolders[0]?.path ?? null)
        setLanguageProfileId(value.langProfiles[0]?.id ?? null)
        setLoad({ loading: false, error: '' })
      })
      .catch(() => {
        if (!cancelled) setLoad({ loading: false, error: 'Download options are unavailable right now.' })
      })
    return () => {
      cancelled = true
    }
  }, [loadMeta])

  const submit = () => {
    if (submitting || qualityProfileId == null || !rootFolderPath) return
    setSubmitting(true)
    setOutcome(null)
    jpost(
      `/api/servarr/${service}/request`,
      requestBody(
        kind,
        item,
        { qualityProfileId, rootFolderPath, languageProfileId: languageProfileId ?? undefined },
        { monitor, searchNow },
      ),
    )
      .then((response) => (response.ok ? apiJson(response) : Promise.reject(response)))
      .then((value: unknown) => {
        const raw = outcomeOf(value)
        const state = outcomeToState(raw)
        if (state === 'grabbed' || state === 'monitoring' || state === 'added') {
          // Definitive. Say what happened, then hand the state back and close —
          // a dialog that vanishes the instant a request lands never tells you
          // which of the three things it did.
          setOutcome({
            tone: 'ok',
            message:
              state === 'grabbed'
                ? 'Downloading — added to your library'
                : state === 'monitoring'
                  ? 'Added — monitoring for releases'
                  : 'Already in your library',
          })
          setTimeout(() => onSettled(state), 900)
        } else if (state === 'no_release') {
          setOutcome({ tone: 'warn', message: 'No release available right now — try again later.' })
        } else {
          setOutcome({ tone: 'error', message: 'Couldn’t check for a release right now. Please try again.' })
        }
        setSubmitting(false)
      })
      .catch(() => {
        setOutcome({ tone: 'error', message: 'Couldn’t start the request. Please try again.' })
        setSubmitting(false)
      })
  }

  const settled = outcome?.tone === 'ok'
  const canSubmit = !load.loading && !load.error && qualityProfileId != null && !!rootFolderPath && !submitting && !settled

  return (
    <DiscoverSheet
      eyebrow="Download options"
      title={item.title}
      subtitle={[item.year, kind === 'series' && item.seasonCount ? `${item.seasonCount} seasons` : null]
        .filter(Boolean)
        .join(' · ') || null}
      item={item}
      motion={motion}
      onClose={onClose}
      busy={submitting}
      footer={
        load.loading || load.error ? null : (
          <button type="button" className="an-action is-primary is-wide" disabled={!canSubmit} onClick={submit}>
            <AnIcon name={settled ? 'check' : 'download'} size={15} />
            <span>
              {submitting
                ? kind === 'movie'
                  ? 'Finding a release…'
                  : 'Adding…'
                : settled
                  ? 'Done'
                  : outcome?.tone === 'warn'
                    ? 'Try again'
                    : 'Download'}
            </span>
          </button>
        )
      }
    >
      {load.loading ? (
        <p className="an-dempty">Loading options…</p>
      ) : load.error ? (
        <SheetNotice tone="error">{load.error}</SheetNotice>
      ) : (
        <>
          <SheetField label="Quality">
            <select
              className="an-dselect"
              value={qualityProfileId ?? ''}
              onChange={(event) => setQualityProfileId(Number(event.target.value))}
            >
              {(meta?.profiles ?? []).map((profile) => (
                <option key={profile.id} value={profile.id}>
                  {profile.name ?? `Profile ${profile.id}`}
                </option>
              ))}
            </select>
          </SheetField>

          <SheetField label="Save to">
            <select
              className="an-dselect"
              value={rootFolderPath ?? ''}
              onChange={(event) => setRootFolderPath(event.target.value)}
            >
              {(meta?.rootFolders ?? []).map((folder) => (
                <option key={folder.id ?? folder.path} value={folder.path}>
                  {folder.path}
                  {folder.freeSpace ? `  (${Math.round(folder.freeSpace / 1e9)} GB free)` : ''}
                </option>
              ))}
            </select>
          </SheetField>

          {kind === 'series' && (meta?.langProfiles.length ?? 0) > 0 ? (
            <SheetField label="Language">
              <select
                className="an-dselect"
                value={languageProfileId ?? ''}
                onChange={(event) => setLanguageProfileId(Number(event.target.value))}
              >
                {(meta?.langProfiles ?? []).map((profile) => (
                  <option key={profile.id} value={profile.id}>
                    {profile.name ?? `Profile ${profile.id}`}
                  </option>
                ))}
              </select>
            </SheetField>
          ) : null}

          {kind === 'series' ? (
            <>
              <SheetToggle
                label="Keep monitoring"
                hint="New episodes download on their own as they appear"
                on={monitor}
                onChange={setMonitor}
              />
              <SheetToggle
                label="Search now"
                hint="Start looking for a release immediately"
                on={searchNow}
                onChange={setSearchNow}
              />
            </>
          ) : null}

          {outcome ? <SheetNotice tone={outcome.tone}>{outcome.message}</SheetNotice> : null}
        </>
      )}
    </DiscoverSheet>
  )
}

/**
 * A switch that is also a checkbox to anything that is not a browser: the state
 * lives on `aria-checked`, not on the colour of a knob.
 */
function SheetToggle({
  label,
  hint,
  on,
  onChange,
}: {
  label: string
  hint: string
  on: boolean
  onChange: (on: boolean) => void
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      className="an-dtoggle"
      onClick={() => onChange(!on)}
    >
      <span className="an-dtoggle-copy">
        <strong>{label}</strong>
        <span>{hint}</span>
      </span>
      <span className="an-dtoggle-track" aria-hidden>
        <i />
      </span>
    </button>
  )
}
