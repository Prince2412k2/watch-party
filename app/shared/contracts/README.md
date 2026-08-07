# Cross-language wire contracts

The same wire contract is implemented three times: once in the server
(`app/server/`, the source of truth), once in the React client
(`app/client/src/sync/`), and once in the Flutter client
(`flutter_app/lib/sync/`, `flutter_app/lib/net/events.dart`). Nothing in the
build links those three together, so until these fixtures existed the two
clients could drift apart — or away from the server — and every suite would
still be green.

The JSON files here are the single canonical description of the parts of the
protocol that must not drift. Each one is consumed by tests in **more than one
language**, so editing a fixture to match one implementation immediately fails
the others:

| Fixture | Consumed by |
|---|---|
| `sync-core.json` | `app/client/src/sync/contractParity.test.ts` (JS)<br>`flutter_app/test/sync/contract_parity_test.dart` (Dart) |
| `socket-events.json` | `app/server/contract.test.js` (JS, server)<br>`app/client/src/sync/contractParity.test.ts` (JS, client)<br>`flutter_app/test/sync/contract_parity_test.dart` (Dart) |

## `sync-core.json`

The playback-sync decision core — `predictPosition` and `decideSyncAction`,
implemented in `app/client/src/sync/syncCore.ts` and ported verbatim to
`flutter_app/lib/sync/sync_core.dart`.

- `constants` — the correction-loop tuning. Both implementations must declare
  every one of these with the same value. (The HLS buffer constants
  `BUFFER_AHEAD_SEC` / `SEEK_TIMEOUT_MS` / `BUFFER_TIMEOUT_MS` /
  `PAUSED_BUFFER_AHEAD_SEC` are deliberately **not** here: they tune the
  browser-only hls.js catch-up path and have no Dart counterpart.)
- `predictPosition` — pure position-prediction cases.
- `decideSyncAction` — one control tick per case. `expect: null` means the tick
  is a no-op. Otherwise `expect` is the *normalized* intent: every field is
  present, with `null` for "not set". Each language normalizes its native
  return value into that shape before comparing, so the fixture pins the
  semantics rather than either language's representation of an absent field.
  `correctionState` / `expectCorrectionState` exercise the soft-nudge
  hysteresis latch.

Floating-point results are compared with a `1e-9` tolerance.

## `socket-events.json`

The socket.io event vocabulary. `clientToServer` is exactly the set the server
registers with `socket.on(...)`; `serverToClient` is exactly the set the server
emits. The server test asserts equality in both directions — the server is the
truth. The two client tests assert that every event name they use or declare
exists in the matching direction, which is what catches a typo or a one-sided
rename.

`syncScheduleFields` is the payload of `sync:schedule`, the one message whose
field names both clients decode by hand.

## Changing the protocol

Change the server, then update the fixture, then update both clients. The
fixture is the middle step on purpose: it is the thing that fails loudly when
one of the three is forgotten.
