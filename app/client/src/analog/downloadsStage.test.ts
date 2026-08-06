// What the Downloads stage says, and what its one destructive control does.
//
// The rail's geometry is already pinned by movieRail.test.ts over the shared
// `railWindow`/`clampRailOffset`; this surface reuses those verbatim, so nothing
// here re-tests them. What IS new is everything the old grid and its detail
// overlay each answered separately: the state vocabulary, the aggregate rates,
// the formatted stats, the three different flavours of "nothing here", and the
// confirmation's default.

import test from 'node:test'
import assert from 'node:assert/strict'
import { isPausedState, stateInfo } from '../lib/format.ts'
import { parseHealth } from '../hooks/downloadsCore.ts'
import {
  DOWNLOADS_MODES,
  DOWNLOADS_MODE_LABELS,
  GAUGE_RING_PX,
  KNOWN_STATES,
  MODE_SERVICES,
  QUEUE_REMOVALS,
  STAGE_POSTER_PX,
  aggregateParts,
  aggregateRates,
  availability,
  catalogParts,
  contextParts,
  downloadState,
  downloadStats,
  entryInitials,
  focusedDownload,
  isDownloadsMode,
  modeAvailability,
  openRemoval,
  parseCatalog,
  primaryAction,
  progressPct,
  queueDetail,
  queueEntry,
  queueKey,
  stageMessage,
  stepDownloadsMode,
  toggleDeleteFiles,
  torrentEntry,
  torrentSubtitle,
  torrentTitle,
  withDeleteFiles,
} from './downloadsStage.ts'

const torrent = (extra: Record<string, unknown> = {}) => ({ hash: 'h1', ...extra })

// ── modes ───────────────────────────────────────────────────────────────────

test('the mode slider is clamped at both ends, never wrapping', () => {
  assert.deepEqual(DOWNLOADS_MODES, ['active', 'attention'])
  assert.equal(stepDownloadsMode('active', -1), 'active')
  assert.equal(stepDownloadsMode('active', 1), 'attention')
  assert.equal(stepDownloadsMode('attention', 1), 'attention')
  assert.equal(stepDownloadsMode('attention', -1), 'active')
  // A burst of scroll deltas cannot be laundered into a jump past a position.
  assert.equal(stepDownloadsMode('active', 9), 'attention')
  assert.equal(stepDownloadsMode('attention', -9), 'active')
  assert.equal(stepDownloadsMode('active', 0), 'active')
})

test('only the two real modes are accepted off the wire', () => {
  assert.equal(isDownloadsMode('active'), true)
  assert.equal(isDownloadsMode('attention'), true)
  for (const value of [null, undefined, '', 'singles', 0, {}]) {
    assert.equal(isDownloadsMode(value), false)
  }
  assert.deepEqual(Object.keys(DOWNLOADS_MODE_LABELS).sort(), ['active', 'attention'])
})

// ── state ───────────────────────────────────────────────────────────────────

test('every state carries a word, so the ring is never the only reading', () => {
  for (const raw of KNOWN_STATES) {
    const mapped = downloadState(raw)
    assert.ok(mapped.label.length > 0, `${raw} produced no status word`)
    assert.notEqual(mapped.label, raw, `${raw} was shown to the user verbatim`)
  }
})

test('the paused set agrees with the formatter every other surface reads', () => {
  // Two mappings of the same vocabulary is exactly how "Pause" ended up showing
  // on a torrent that was already stopped. They are allowed to disagree about
  // wording; they may not disagree about whether the button says Pause.
  for (const raw of KNOWN_STATES) {
    assert.equal(
      downloadState(raw).paused,
      isPausedState(raw),
      `${raw} is paused in one mapping and not the other`,
    )
  }
  assert.equal(downloadState(undefined).paused, isPausedState(undefined))
})

test('an unrecognised state is shown rather than swallowed', () => {
  // Reporting a real state as "Unknown" would hide a working download behind a
  // shrug; only a genuinely absent one gets the placeholder.
  assert.equal(downloadState('moving').label, 'moving')
  assert.equal(downloadState('').label, 'Unknown')
  assert.equal(downloadState(null).label, 'Unknown')
  assert.equal(stateInfo('moving').label, 'moving')
})

test('status colour is reserved for the two states that mean something', () => {
  const tones = new Map(KNOWN_STATES.map((raw) => [raw, downloadState(raw).tone]))
  assert.equal(tones.get('error'), 'danger')
  assert.equal(tones.get('missingFiles'), 'danger')
  assert.equal(tones.get('pausedUP'), 'success')
  assert.equal(tones.get('stoppedUP'), 'success')
  for (const raw of ['downloading', 'stalledDL', 'queuedDL', 'pausedDL', 'uploading']) {
    assert.equal(tones.get(raw), 'neutral', `${raw} claimed a semantic colour it has not earned`)
  }
})

test('a failed download offers a retry, not a resume', () => {
  assert.deepEqual(primaryAction(downloadState('error')), {
    kind: 'retry',
    label: 'Retry',
    disabled: false,
  })
  assert.deepEqual(primaryAction(downloadState('pausedDL')), {
    kind: 'resume',
    label: 'Resume',
    disabled: false,
  })
  assert.deepEqual(primaryAction(downloadState('downloading')), {
    kind: 'pause',
    label: 'Pause',
    disabled: false,
  })
  // Finished: the control stays put and says so, rather than vanishing and
  // reflowing the action row under the pointer.
  assert.deepEqual(primaryAction(downloadState('pausedUP')), {
    kind: 'none',
    label: 'Completed',
    disabled: true,
  })
  // An action already in flight is not offered twice.
  assert.equal(primaryAction(downloadState('downloading'), true).disabled, true)
  assert.equal(primaryAction(downloadState('error'), true).kind, 'retry')
})

// ── numbers ─────────────────────────────────────────────────────────────────

test('progress is clamped to whole percents', () => {
  assert.equal(progressPct(0), 0)
  assert.equal(progressPct(0.5), 50)
  assert.equal(progressPct(0.9999), 100)
  assert.equal(progressPct(1), 100)
  // A client that reports out of range must not produce a ring that overruns.
  assert.equal(progressPct(4), 100)
  assert.equal(progressPct(-1), 0)
  assert.equal(progressPct(null), 0)
  assert.equal(progressPct(undefined), 0)
  assert.equal(progressPct(Number.NaN), 0)
})

test('the stats block reads in units, and hides the ETA sentinel', () => {
  const live = torrent({
    state: 'downloading',
    dlspeed: 4_400_000,
    upspeed: 0,
    eta: 754,
    numSeeds: 24,
    numLeechs: 3,
    size: 1_500_000_000,
  })
  assert.deepEqual(downloadStats(live, downloadState('downloading')), [
    '↓ 4.2 MB/s',
    '↑ 0 B/s',
    'ETA 12m',
    'Seeds 24',
    'Peers 3',
    '1.4 GB',
  ])

  // 8640000 is the download client's "unknown/forever" marker.
  assert.equal(downloadStats(torrent({ eta: 8_640_000 }), downloadState('stalledDL'))[2], 'ETA ∞')
  // A finished transfer has no arrival time at all.
  assert.equal(downloadStats(torrent({ eta: 0 }), downloadState('pausedUP'))[2], 'ETA —')

  // Every field past the hash is optional on the wire; none of them may render
  // as "undefined" or crash the block that shows the rest.
  assert.deepEqual(downloadStats(torrent(), downloadState('downloading')), [
    '↓ 0 B/s',
    '↑ 0 B/s',
    'ETA ∞',
    'Seeds 0',
    'Peers 0',
    '—',
  ])
  // A non-numeric value off a loosely typed record is treated as absent.
  assert.equal(downloadStats(torrent({ numSeeds: 'lots' }), downloadState('downloading'))[3], 'Seeds 0')
})

test('the aggregate is the sum of the whole list, not of the active ones', () => {
  const list = [
    torrent({ hash: 'a', dlspeed: 1_000_000, upspeed: 250_000 }),
    torrent({ hash: 'b', dlspeed: 500_000, upspeed: 0, state: 'pausedDL' }),
    torrent({ hash: 'c' }),
  ]
  assert.deepEqual(aggregateRates(list), { downBps: 1_500_000, upBps: 250_000, total: 3 })
  assert.deepEqual(aggregateRates([]), { downBps: 0, upBps: 0, total: 0 })

  // The count comes from the hub, which is what the nav badge shows: deriving a
  // second one here is how two "N downloading" readings drift apart.
  assert.deepEqual(aggregateParts(aggregateRates(list), 1), [
    '1 downloading',
    '↓ 1.4 MB/s',
    '↑ 244 KB/s',
  ])
  // Nothing in the list at all: the header line is absent, not "0 downloading".
  assert.deepEqual(aggregateParts(aggregateRates([]), 0), [])
})

// ── availability ────────────────────────────────────────────────────────────

test('configured-but-unreachable reads differently from never-configured', () => {
  const health = (services: Record<string, unknown>) => parseHealth({ services })

  assert.equal(
    availability(health({ qbittorrent: { configured: true, reachable: true } }), false, ['qbittorrent']),
    'ready',
  )
  assert.equal(
    availability(health({ qbittorrent: { configured: true, reachable: false } }), false, ['qbittorrent']),
    'unreachable',
  )
  assert.equal(
    availability(health({ qbittorrent: { configured: false, reachable: false } }), false, ['qbittorrent']),
    'unconfigured',
  )
  assert.equal(availability(health({}), false, ['qbittorrent']), 'unconfigured')
  // Before the first health response nothing is claimed either way.
  assert.equal(availability(null, true, ['qbittorrent']), 'loading')
})

test('either library manager being usable is enough for the attention rail', () => {
  const health = (services: Record<string, unknown>) => parseHealth({ services })
  assert.deepEqual(MODE_SERVICES.attention, ['radarr', 'sonarr'])

  assert.equal(modeAvailability('attention', health({ sonarr: { configured: true, reachable: true } }), false), 'ready')
  // One up and one down is still usable; the down one must not demote it.
  assert.equal(
    modeAvailability(
      'attention',
      health({ radarr: { configured: true, reachable: false }, sonarr: { configured: true, reachable: true } }),
      false,
    ),
    'ready',
  )
  assert.equal(
    modeAvailability('attention', health({ radarr: { configured: true, reachable: false } }), false),
    'unreachable',
  )
  assert.equal(modeAvailability('attention', health({}), false), 'unconfigured')
})

test('each nothing-here state says which nothing it is', () => {
  const unreachable = stageMessage('active', 'unreachable', 0)!
  const unconfigured = stageMessage('active', 'unconfigured', 0)!
  const empty = stageMessage('active', 'ready', 0)!

  assert.notEqual(unreachable.title, unconfigured.title)
  assert.notEqual(unreachable.title, empty.title)
  // The transient one has to say it resolves itself; the permanent one must not.
  assert.match(unreachable.hint, /on their own/)
  assert.match(unconfigured.hint, /Connect/)

  // A loaded rail with something on it has nothing to say instead of the item,
  // and neither does one still waiting for its first response.
  assert.equal(stageMessage('active', 'ready', 3), null)
  assert.equal(stageMessage('active', 'loading', 0), null)

  // Both modes answer, and they do not share copy — "nothing downloading" and
  // "nothing stuck" are different pieces of news.
  assert.notEqual(stageMessage('attention', 'ready', 0)!.title, empty.title)
  assert.notEqual(stageMessage('attention', 'unconfigured', 0)!.title, unconfigured.title)
})

// ── rail entries ────────────────────────────────────────────────────────────

test('a download with no title of its own is still listed', () => {
  assert.equal(torrentTitle(torrent({ displayTitle: 'Dune (2021)', name: 'dune.2021.mkv' })), 'Dune (2021)')
  assert.equal(torrentTitle(torrent({ name: 'dune.2021.mkv' })), 'dune.2021.mkv')
  assert.equal(torrentTitle(torrent({ displayTitle: '  ' })), 'Untitled download')
  assert.equal(torrentTitle(torrent()), 'Untitled download')
})

test('the second line never repeats the first', () => {
  assert.equal(torrentSubtitle(torrent({ subtitle: 'S01E04 · 1080p' })), 'S01E04 · 1080p')
  // No subtitle, but a release name that says more than the resolved title.
  assert.equal(torrentSubtitle(torrent({ displayTitle: 'Dune', name: 'dune.2021.mkv' })), 'dune.2021.mkv')
  assert.equal(torrentSubtitle(torrent({ displayTitle: 'Dune', name: 'Dune' })), null)
  assert.equal(torrentSubtitle(torrent()), null)
})

test('the rail badge marks the exceptions, not the ordinary case', () => {
  // Normal progress is already drawn as a bar across the poster; repeating it as
  // a badge would be the percentage twice and the state nowhere.
  assert.equal(torrentEntry(torrent({ state: 'downloading', progress: 0.4 })).badge, null)
  assert.equal(torrentEntry(torrent({ state: 'stalledDL' })).badge, null)
  assert.equal(torrentEntry(torrent({ state: 'pausedDL' })).badge, 'Paused')
  assert.equal(torrentEntry(torrent({ state: 'error' })).badge, 'Failed')
  assert.equal(torrentEntry(torrent({ state: 'pausedUP' })).badge, 'Completed')
})

test('a rail entry keeps a stable key and its own artwork', () => {
  const entry = torrentEntry(torrent({
    hash: 'abc',
    displayTitle: 'Dune',
    posterUrl: 'https://image.tmdb.org/x.jpg',
    kind: 'movie',
    progress: 0.42,
  }))
  assert.deepEqual(entry, {
    key: 'abc',
    title: 'Dune',
    posterUrl: 'https://image.tmdb.org/x.jpg',
    kind: 'movie',
    progressPct: 42,
    badge: null,
  })
  // An empty poster string is no poster; rendering it would request the page.
  assert.equal(torrentEntry(torrent({ posterUrl: '  ' })).posterUrl, null)
})

test('a stuck grab has no progress to draw and says so instead', () => {
  const entry = queueEntry({ id: 7, service: 'radarr', title: 'Dune (2021)' })
  assert.equal(entry.key, 'radarr:7')
  assert.equal(entry.title, 'Dune (2021)')
  assert.equal(entry.progressPct, null, 'a grab that never started has no progress bar')
  assert.equal(entry.badge, 'Stuck')
  assert.equal(entry.posterUrl, null)

  // Radarr and Sonarr number their queues independently, so the service has to
  // be part of the key or two records collide and the rail loses one.
  assert.notEqual(queueKey({ id: 7, service: 'radarr' }), queueKey({ id: 7, service: 'sonarr' }))
  assert.equal(queueEntry({ id: 1, service: 'sonarr' }).title, 'Untitled item')
})

test('a stuck grab always states a reason and where it came from', () => {
  assert.deepEqual(queueDetail({ id: 1, service: 'radarr', statusMessages: ['No files found'], indexer: 'nzb', size: 1024 }), {
    reasons: ['No files found'],
    meta: ['nzb', '1.0 KB'],
  })
  // "Needs attention" with no stated reason is not actionable.
  assert.deepEqual(queueDetail({ id: 1, service: 'sonarr' }).reasons, ['No reason given.'])
  assert.deepEqual(queueDetail({ id: 1, service: 'sonarr' }).meta, ['—'])
})

test('a download with no artwork falls back to fixed-size initials', () => {
  // One letter per word, up to two — the same chain library artwork falls back
  // through, so a poster-less download does not look like a different species.
  assert.equal(entryInitials('Dune Part Two'), 'DP')
  assert.equal(entryInitials('Dune'), 'D')
  assert.equal(entryInitials('  the expanse  '), 'TE')
  assert.equal(entryInitials('   '), '—')
  assert.equal(entryInitials(''), '—')
})

// ── catalog enrichment ──────────────────────────────────────────────────────

test('the catalog lookup is narrowed field by field', () => {
  const parsed = parseCatalog({
    title: 'Dune: Part Two',
    subtitle: ' 2160p WEB-DL ',
    posterUrl: 'https://image.tmdb.org/x.jpg',
    overview: 'Paul unites with the Fremen.',
    genres: ['Sci-Fi', 42, 'Adventure', '  '],
    rating: 8.2,
    runtime: 166,
    year: 2024,
    certification: 'PG-13',
    network: null,
    status: 'released',
  })!
  assert.equal(parsed.subtitle, '2160p WEB-DL', 'whitespace was carried into the layout')
  assert.deepEqual(parsed.genres, ['Sci-Fi', 'Adventure'], 'a non-string genre reached the meta line')
  assert.equal(parsed.year, '2024', 'a numeric year must be rendered, not concatenated')
  assert.equal(parsed.network, null)

  // *arr sends a string year for a series that ran over several.
  assert.equal(parseCatalog({ year: '2015-2022' })!.year, '2015-2022')

  // Nothing about the lookup is guaranteed: it answers from whichever *arr knows
  // the download, and a manual torrent belongs to neither.
  const bare = parseCatalog({})!
  assert.deepEqual(bare.genres, [])
  assert.equal(bare.title, null)
  assert.equal(bare.rating, null)
  for (const value of [null, undefined, 'nope', 7, []]) {
    assert.equal(parseCatalog(value), null)
  }
})

test('the catalog line closes its own gaps', () => {
  assert.deepEqual(
    catalogParts(parseCatalog({ rating: 8.25, runtime: 166, year: 2024, certification: 'PG-13', genres: ['Sci-Fi'] })),
    ['★ 8.3', '2h 46m', '2024', 'PG-13', 'Sci-Fi'],
  )
  // A record with none of it must not produce a row of separators.
  assert.deepEqual(catalogParts(parseCatalog({})), [])
  assert.deepEqual(catalogParts(null), [])
  // Genres are capped: the line is context, not a tag cloud.
  assert.equal(catalogParts(parseCatalog({ genres: ['a', 'b', 'c', 'd', 'e'] })).length, 3)
  // A zero runtime is absent, not "0m".
  assert.deepEqual(catalogParts(parseCatalog({ runtime: 0 })), [])
})

test('the catalog wins over the torrent, and absence never blanks the stage', () => {
  const record = torrent({
    displayTitle: 'Dune',
    name: 'dune.2024.mkv',
    posterUrl: 'https://qbit/poster.jpg',
  })

  // No lookup yet: the stage still renders, off what the download client knows.
  assert.deepEqual(focusedDownload(record, null), {
    title: 'Dune',
    subtitle: 'dune.2024.mkv',
    posterUrl: 'https://qbit/poster.jpg',
    overview: null,
  })

  // Once it lands it is the same download with strictly better copy.
  const catalog = parseCatalog({
    title: 'Dune: Part Two',
    subtitle: '2160p WEB-DL',
    posterUrl: 'https://image.tmdb.org/x.jpg',
    overview: 'Paul unites with the Fremen.',
  })
  assert.deepEqual(focusedDownload(record, catalog), {
    title: 'Dune: Part Two',
    subtitle: '2160p WEB-DL',
    posterUrl: 'https://image.tmdb.org/x.jpg',
    overview: 'Paul unites with the Fremen.',
  })

  // A lookup that resolved nothing must not erase what was already showing.
  assert.equal(focusedDownload(record, parseCatalog({})).title, 'Dune')
  assert.equal(focusedDownload(record, parseCatalog({})).posterUrl, 'https://qbit/poster.jpg')
})

test('the release line is never printed twice', () => {
  const catalog = parseCatalog({ subtitle: '2160p WEB-DL', year: 2024 })
  const record = torrent({ displayTitle: 'Dune' })

  // No synopsis: the release line IS the paragraph, so it stays out of the
  // context line.
  const plain = focusedDownload(record, catalog)
  assert.deepEqual(contextParts(plain, catalog), ['2024'])

  // With a synopsis the paragraph is taken, so the release line moves up.
  const withOverview = focusedDownload(record, parseCatalog({ subtitle: '2160p WEB-DL', year: 2024, overview: 'Paul.' }))
  assert.deepEqual(contextParts(withOverview, parseCatalog({ subtitle: '2160p WEB-DL', year: 2024, overview: 'Paul.' })), [
    '2160p WEB-DL',
    '2024',
  ])

  assert.deepEqual(contextParts(focusedDownload(record, null), null), [])
})

// ── removal ─────────────────────────────────────────────────────────────────

test('remove-with-files defaults to OFF every time the confirmation opens', () => {
  const first = openRemoval(torrent({ hash: 'a', displayTitle: 'Dune' }))
  assert.equal(first.deleteFiles, false, 'erasing the data on disk is never the default')
  assert.equal(first.hash, 'a')
  assert.equal(first.title, 'Dune')

  // Turning it on for one download must not arm it for the next: the intent is
  // created per-open, so a second confirmation cannot inherit the first answer.
  const armed = toggleDeleteFiles(first)
  assert.equal(armed.deleteFiles, true)
  assert.equal(first.deleteFiles, false, 'the toggle mutated the intent it was given')
  assert.equal(openRemoval(torrent({ hash: 'b' })).deleteFiles, false)

  // And it is a toggle, not a latch.
  assert.equal(toggleDeleteFiles(armed).deleteFiles, false)
  assert.equal(withDeleteFiles(first, true).deleteFiles, true)
  assert.equal(withDeleteFiles(armed, false).deleteFiles, false)
})

test('blocking a release is a second choice, never a default', () => {
  assert.equal(QUEUE_REMOVALS.length, 2)
  assert.equal(QUEUE_REMOVALS[0].blocklist, false, 'the reversible removal comes first')
  assert.equal(QUEUE_REMOVALS[1].blocklist, true)
  for (const choice of QUEUE_REMOVALS) {
    assert.ok(choice.label.length > 0)
    assert.ok(choice.hint.length > 0, 'a destructive choice has to say what it does')
  }
})

// ── sizing ──────────────────────────────────────────────────────────────────

test('the stage poster and its gauge shrink together, never to nothing', () => {
  for (const size of ['phone', 'tablet', 'desktop'] as const) {
    assert.ok(STAGE_POSTER_PX[size] > 0)
    assert.ok(GAUGE_RING_PX[size] > 0)
    // The gauge sits under the poster, so it must never be the wider of the two.
    assert.ok(GAUGE_RING_PX[size] <= STAGE_POSTER_PX[size], `${size} gauge overruns its column`)
  }
  assert.ok(STAGE_POSTER_PX.phone < STAGE_POSTER_PX.tablet)
  assert.ok(STAGE_POSTER_PX.tablet < STAGE_POSTER_PX.desktop)
})
