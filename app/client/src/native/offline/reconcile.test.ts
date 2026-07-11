import test from 'node:test'
import assert from 'node:assert/strict'

import { __setMockTransport, invoke, listen } from '../ipc'
import { IPC, EVENTS } from '../contract.ts'
import { reconcileList, applyStart, applyProgress, applyDone, applyError, toSortedList } from './reconcile'

// A tiny fake Tauri transport: dl_list() returns whatever `state.records`
// currently holds, and listen() registers a handler this test can fire
// directly — mirroring what the real MpvBackend/offline-UI tests do against
// __setMockTransport, but exercising the dl_*/dl:* side of the contract N2 owns.
function makeMockTransport() {
  const state = { records: [] }
  const handlers = {}
  const invokeCalls = []

  const mockInvoke = async (cmd, payload) => {
    invokeCalls.push([cmd, payload])
    if (cmd === IPC.DL_LIST) return state.records
    if (cmd === IPC.DL_START) return { id: 'dl-1' }
    return {}
  }
  const mockListen = async (eventName, handler) => {
    handlers[eventName] = handler
    return () => {
      delete handlers[eventName]
    }
  }
  const fire = (eventName, payload) => handlers[eventName]?.({ payload })

  return { state, invokeCalls, mockInvoke, mockListen, fire }
}

test('reconcile core: queued -> active -> done via dl:progress/dl:done, seeded from dl_list()', async () => {
  const { state, mockInvoke, mockListen, fire } = makeMockTransport()
  __setMockTransport({ invoke: mockInvoke, listen: mockListen })

  // dl_list() is the source of truth for the initial seed.
  state.records = [
    { id: 'dl-1', itemId: 'item-1', title: 'The Movie', state: 'queued', receivedBytes: 0, totalBytes: 1000, parts: 4 },
  ]
  let map = reconcileList(new Map(), await invoke(IPC.DL_LIST))
  assert.equal(map.get('dl-1').state, 'queued')

  // Register the same listeners the hook would, then drive them exactly like
  // the real Rust backend would emit dl:progress -> dl:done.
  await listen(EVENTS.DL_PROGRESS, ({ payload }) => {
    map = applyProgress(map, payload)
  })
  await listen(EVENTS.DL_DONE, ({ payload }) => {
    map = applyDone(map, payload)
  })
  await listen(EVENTS.DL_ERROR, ({ payload }) => {
    map = applyError(map, payload)
  })

  fire(EVENTS.DL_PROGRESS, { id: 'dl-1', receivedBytes: 400, totalBytes: 1000, bytesPerSec: 2048 })
  assert.equal(map.get('dl-1').state, 'active')
  assert.equal(map.get('dl-1').receivedBytes, 400)
  assert.equal(map.get('dl-1').bytesPerSec, 2048)
  // fields not carried by the progress event must survive from the seed
  assert.equal(map.get('dl-1').title, 'The Movie')
  assert.equal(map.get('dl-1').parts, 4)

  fire(EVENTS.DL_PROGRESS, { id: 'dl-1', receivedBytes: 1000, totalBytes: 1000, bytesPerSec: 1500 })
  assert.equal(map.get('dl-1').receivedBytes, 1000)

  fire(EVENTS.DL_DONE, { id: 'dl-1', itemId: 'item-1', path: '/offline/item-1.mkv' })
  assert.equal(map.get('dl-1').state, 'done')
  assert.equal(map.get('dl-1').path, '/offline/item-1.mkv')
  assert.equal(map.get('dl-1').receivedBytes, 1000, 'done should retain the final byte count')

  // A later dl_list() poll (e.g. after relaunch) reconciling the same id must
  // not regress the done state or drop the title.
  state.records = [
    { id: 'dl-1', itemId: 'item-1', title: 'The Movie', state: 'done', receivedBytes: 1000, totalBytes: 1000, parts: 4 },
  ]
  map = reconcileList(map, await invoke(IPC.DL_LIST))
  assert.equal(map.get('dl-1').state, 'done')

  assert.deepEqual(toSortedList(map).map((r) => r.id), ['dl-1'])
})

test('reconcile core: dl:error flips an active download to error and preserves the message', async () => {
  let map = applyStart(new Map(), { id: 'dl-2', itemId: 'item-2', title: 'Another Movie', parts: 2 })
  map = applyProgress(map, { id: 'dl-2', receivedBytes: 200, totalBytes: 5000, bytesPerSec: 900 })
  assert.equal(map.get('dl-2').state, 'active')

  map = applyError(map, { id: 'dl-2', message: 'connection reset' })
  assert.equal(map.get('dl-2').state, 'error')
  assert.equal(map.get('dl-2').message, 'connection reset')
  // byte progress made before the error is preserved for the UI to show "got this far"
  assert.equal(map.get('dl-2').receivedBytes, 200)
})

test('reconcile core: applyStart seeds a queued record with zeroed progress', () => {
  const map = applyStart(new Map(), { id: 'dl-3', itemId: 'item-3', title: 'Third Movie', parts: 6 })
  assert.deepEqual(map.get('dl-3'), {
    id: 'dl-3',
    itemId: 'item-3',
    title: 'Third Movie',
    state: 'queued',
    receivedBytes: 0,
    totalBytes: 0,
    parts: 6,
    bytesPerSec: 0,
  })
})
