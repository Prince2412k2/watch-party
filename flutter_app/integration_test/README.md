# Opt-in integration tests

Nothing in this directory runs during `flutter test` or in CI. Everything here
needs something the build machine does not have — a live backend, a LiveKit
server, a webcam, a real Linux desktop — so each test is run deliberately, by
name, against an environment you have set up.

`flutter analyze` **does** cover this directory, and CI runs it. That is what
keeps these tests from rotting: a breaking change to `DioApiClient`, the
Riverpod providers, or `MediaKitPlayerController` fails the analyzer the day it
lands, even though nobody ran the test.

## Live-backend tests (host VM, no device needed)

| Test | What it proves |
|---|---|
| `api_client_test.dart` | `DioApiClient` logs in as root/root, the session cookie carries to `/me`, and `/api/library/items` returns items |
| `auth_provider_test.dart` | `authProvider` reaches authenticated state, and `restore()` re-authenticates from a persisted cookie jar across a simulated restart |
| `library_provider_test.dart` | The E3 providers (home / browse / search / detail) load real Jellyfin data |

Start the backend from the repo root:

```bash
cd app && npm start          # :3001 unless PORT says otherwise
```

Then from `flutter_app/`:

```bash
flutter test integration_test/api_client_test.dart \
             integration_test/auth_provider_test.dart \
             integration_test/library_provider_test.dart \
             --dart-define=API_BASE=http://localhost:3001
```

`API_BASE` defaults to `http://localhost:3005`, the port the Flutter desktop
dev setup uses. The backend needs a `root`/`root` Jellyfin account with a
non-empty library. Login is rate-limited to 10 attempts per 5 minutes per IP,
so `library_provider_test` logs in exactly once and reuses the persisted cookie
jar for every provider it exercises — keep that property if you add cases.

### Why these three moved here

They used to live in `test/` and call `markTestSkipped('backend not reachable')`
whenever no server answered. That looked harmless, but it meant four tests
reported "skipped" on every unattended run — CI included, where a backend has
never been available. A skip nobody can turn into a pass is not coverage; it is
noise that hides the fact that the coverage is missing. `flutter test` now has
zero skips, and because running these is a deliberate act, an unreachable
backend **fails** instead of skipping (see `requireBackend` in `backend.dart`).

## Device tests (need `-d linux` and hardware)

| Test | Also needs |
|---|---|
| `player_live_test.dart` | backend on `:3005` and a Linux desktop device; plays a known item through libmpv and asserts the position stream advances |
| `livekit_room_test.dart` | a LiveKit server + token in `/tmp/wp-spike-livekit.txt`, and a real `/dev/video0` |
| `downloader_test.dart` | see the header comment in the file |

```bash
flutter test integration_test/player_live_test.dart -d linux
```
