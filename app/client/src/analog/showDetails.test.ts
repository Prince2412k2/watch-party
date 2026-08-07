// What the Shows stage says about the focused item, and what reaches the player
// when Enter is pressed on it.
//
// Two failure modes are worth guarding here because both look fine on screen
// until the wrong thing happens: a series offering Play (there is no file behind
// it, so the player opens on nothing), and a subtitle choice that does not
// survive into the query string (the player falls back to the file's default and
// turns subtitles back on for someone who just turned them off).

import test from 'node:test'
import assert from 'node:assert/strict'
import { episodeCode, showActions, showContext, showPlayLabel, type ShowStageItem } from './showDetails.ts'
import {
  defaultSelection,
  playbackQuery,
  wireSelection,
  type PlaybackTracks,
} from './playbackTracks.ts'

const episode = (over: Partial<ShowStageItem> = {}): ShowStageItem => ({
  Id: 'e1',
  Name: 'A Study in Pink',
  Type: 'Episode',
  SeriesName: 'Sherlock',
  ParentIndexNumber: 1,
  IndexNumber: 1,
  ...over,
})

const series = (over: Partial<ShowStageItem> = {}): ShowStageItem => ({
  Id: 'show',
  Name: 'Sherlock',
  Type: 'Series',
  ChildCount: 4,
  ...over,
})

// ── naming ──────────────────────────────────────────────────────────────────

test('an episode says which slot it fills, including Specials', () => {
  assert.equal(episodeCode(episode()), 'S1 · E1')
  // Season 0 is Specials and is a real season. A falsy test here renders every
  // special as a bare "E4" with no idea which show it belongs to.
  assert.equal(episodeCode(episode({ ParentIndexNumber: 0, IndexNumber: 4 })), 'S0 · E4')
  assert.equal(episodeCode(episode({ ParentIndexNumber: null })), 'E1')
  assert.equal(episodeCode(episode({ IndexNumber: null })), 'S1')
  assert.equal(episodeCode(episode({ ParentIndexNumber: null, IndexNumber: null })), null)
})

test('the eyebrow says what the title on the stage cannot', () => {
  // The stage's headline is the EPISODE's name, so without this the screen never
  // says which show you are looking at.
  assert.equal(showContext(episode()), 'Sherlock · S1 · E1')
  // Some episode payloads carry SeriesId but not SeriesName; the series drilled
  // into is the fallback.
  assert.equal(showContext(episode({ SeriesName: null }), 'Sherlock'), 'Sherlock · S1 · E1')
  assert.equal(showContext(episode({ SeriesName: null, ParentIndexNumber: null, IndexNumber: null }), null), null)

  assert.equal(showContext(series()), '4 seasons')
  assert.equal(showContext(series({ ChildCount: 1 })), '1 season')
  assert.equal(showContext(series({ ChildCount: 0 })), null)
  assert.equal(showContext(null), null)
  assert.equal(showContext({ Id: 'm', Name: 'Heat', Type: 'Movie' }), null)
})

// ── actions ─────────────────────────────────────────────────────────────────

test('a series opens; only an episode plays', () => {
  const opens = showActions(series(), true)
  assert.deepEqual(opens, { plays: false, label: 'Open 4 seasons', tracks: false, download: false })
  assert.equal(showPlayLabel(series({ ChildCount: 1 })), 'Open 1 season')
  // A show whose seasons have not been counted still has to offer a way in.
  assert.equal(showPlayLabel(series({ ChildCount: null })), 'Open series')

  const plays = showActions(episode(), true)
  assert.deepEqual(plays, { plays: true, label: 'Play', tracks: true, download: true })
})

test('an episode resumes from where it was left', () => {
  // 90 minutes in ticks: 5400 seconds at 10,000,000 ticks per second.
  assert.equal(showPlayLabel(episode({ UserData: { PlaybackPositionTicks: 54_000_000_000 } })), 'Resume 1h 30m')
  assert.equal(showPlayLabel(episode({ UserData: { PlaybackPositionTicks: 0 } })), 'Play')
  assert.equal(showPlayLabel(episode({ UserData: null })), 'Play')
  assert.equal(showPlayLabel(null), 'Play')
})

test('offline download is native-shell only', () => {
  // A browser tab has nowhere to put the file, so the control is absent rather
  // than rendered permanently dead on a primary surface.
  assert.equal(showActions(episode(), false).download, false)
  assert.equal(showActions(episode(), true).download, true)
  assert.equal(showActions(series(), true).download, false)
  assert.deepEqual(showActions(null, true), { plays: false, label: 'Play', tracks: false, download: false })
})

// ── track selection reaching the player ─────────────────────────────────────

const tracks = (over: Partial<PlaybackTracks> = {}): PlaybackTracks => ({
  mediaSourceId: 'ms1',
  audioStreams: [],
  subtitleStreams: [],
  ...over,
})

const track = (index: number, over: Record<string, unknown> = {}) => ({
  index,
  isDefault: false,
  isForced: false,
  isExternal: false,
  ...over,
})

test('an episode opens on the file’s default audio with subtitles off', () => {
  const dubbed = tracks({
    audioStreams: [track(1, { language: 'jpn' }), track(2, { language: 'eng', isDefault: true })],
    subtitleStreams: [track(3, { language: 'eng' })],
  })
  assert.deepEqual(defaultSelection(dubbed), { audioStreamIndex: 2, subtitleStreamIndex: null })

  // A forced track carries dialogue the viewer cannot otherwise follow — signs
  // and songs on a subbed episode — so suppressing it is worse than showing it.
  const forced = tracks({
    audioStreams: [track(1)],
    subtitleStreams: [track(2, { isForced: true }), track(3)],
  })
  assert.equal(defaultSelection(forced).subtitleStreamIndex, 2)

  // No audio marked default: the first track, because "no audio" is not a state
  // anyone wants.
  assert.equal(defaultSelection(tracks({ audioStreams: [track(7), track(8)] })).audioStreamIndex, 7)
  assert.deepEqual(defaultSelection(tracks()), { audioStreamIndex: null, subtitleStreamIndex: null })
})

test('the chosen tracks survive into the player’s query string', () => {
  const chosen = wireSelection({ audioStreamIndex: 2, subtitleStreamIndex: 3 })
  assert.equal(String(playbackQuery('e1', chosen)), 'itemId=e1&audioStreamIndex=2&subtitleStreamIndex=3')

  // "Off" is -1 and MUST be carried. Dropping the key would let the player fall
  // back to the file's default and turn subtitles back on.
  const off = wireSelection({ audioStreamIndex: 2, subtitleStreamIndex: null })
  assert.equal(String(playbackQuery('e1', off)), 'itemId=e1&audioStreamIndex=2&subtitleStreamIndex=-1')

  // No menu was ever opened: nothing is asserted, and the player keeps its own
  // defaulting rather than being pinned to index 0.
  assert.equal(String(playbackQuery('e1')), 'itemId=e1')
  assert.equal(String(playbackQuery('e1', { audioStreamIndex: null, subtitleStreamIndex: null })), 'itemId=e1')
})
