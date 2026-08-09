# Handoff — Watchparty

Written at the end of a long session. Every fact below was checked against the
tree, the remote, or the box — not recalled.

**Local `dev` = `origin/dev` = `08686f4`. Nothing unpushed.**
`origin/main` = `09d07d9`, and its deploy **succeeded**. Production is healthy.

`dev` is 8 ahead of `main` and 4 behind it (main carries merge commits dev does
not). The 8 are all Flutter-side fixes from the tail of this session.

---

## 0. Read this first

Five things that will otherwise cost you an hour each. All were learned the
expensive way in this session.

1. **`flutter` is not on the Bash `PATH`.** It only runs inside a Herdr pane.
   And a fresh pane starts at the REPO ROOT, where `flutter analyze` analyzes
   the root package, finds nothing, and prints `No issues found!` — identical to
   a real pass. Set the pane's cwd as its own command first:
   ```bash
   herdr pane run <id> "cd /home/princepatel/projects/watch_party/flutter_app"
   herdr pane run <id> "clear ; flutter analyze ..."
   ```
   This produced three false passes before it was noticed.

2. **Never read verification off the terminal.** Write it to a file in the repo
   and wait for an explicit completion marker:
   ```bash
   herdr pane run <id> "flutter analyze > .analyze.tmp 2>&1 ; flutter test > .test.tmp 2>&1 ; echo DONE > .done.tmp"
   until [ -f .done.tmp ]; do sleep 6; done
   ```
   Reading `.test.tmp` mid-write showed an in-progress `-2` that was taken for a
   result. Two changes were then made reasoning from it. Both "failures" were
   imaginary. (Your `/tmp` and the pane's are different views — put the file in
   the repo.)

3. **Use `Edit`/`Write`, never Python heredocs, for Dart.** `\$` inside a Python
   string becomes a literal `\$` in Dart and silently breaks string
   interpolation. This is documented in an older handoff and it still happened
   again this session.

4. **The browse stage is the reference; the detail page follows it.** Both read
   placement and type from `lib/app/screens/title_layout.dart`.

5. **Analyze-only.** The user asked for no `flutter build` to keep iteration
   fast. `flutter analyze` clean + `flutter test` green is the bar. CI does the
   real compile. **Baseline: 425 tests.**

---

## 1. Production

Healthy, all containers up ~5h, deploy green.

**Three faults were found and fixed on the box this session.** All are now also
correct in git, but the story matters because two of them were invisible:

- **bazarr was pinned BEHIND its own database.** A v1.6.0 bazarr had migrated
  the config volume; the pin said v1.5.6, which cannot resolve that revision.
  It sat unhealthy, and `watchparty` declares `bazarr: condition:
  service_healthy`, so the app would not start. Rolled forward to
  `v1.6.0-ls357`.
- **`data/` was root-owned.** The app runs as uid 1000, so SQLite opened
  read-only and the server crash-looped on import. `chown -R 1000:1000 data`.
- **coturn's `external-ip` was the literal `YOUR_VPS_PUBLIC_IP`.** That is the
  address TURN advertises as its relay candidate, so TURN relay had NEVER
  worked — invisible, because STUN covers most clients and only users behind
  symmetric NAT silently fail. `up-prod.sh` now asserts it against
  `VPS_PUBLIC_IP`.

**Deploy path:** CI on a push to `main` SSHes in and runs `./deploy/up-prod.sh`,
then `./deploy/health-check.sh`. That script is now the ONLY bring-up path —
the deploy job used to open-code a subset of it and skipped the ownership check
that would have caught the crash-loop.

**Do not edit `docker-compose.prod.yml` on the box.** The deploy does
`git pull --ff-only`, which a dirty tracked file breaks.

**`secrets/` is gitignored and lives only on the VPS.** A rebuild from
`coturn.conf.example` reintroduces the placeholder.

---

## 2. Credentials

The PAT is **read-only**. It cannot push, merge, or re-run jobs. It CAN read
the API. SSH to github is unreachable from this container (port 22 blocked,
`ssh.github.com` does not resolve). The user pushes and merges.

For the VPS there is a live SSH session in a Herdr pane — find it with
`herdr pane list` and look for the one whose output is on the box. It is
sometimes occupied by a TUI (lazydocker); commands silently do nothing then.

## 3. Architecture worth knowing

**Design tokens are generated.** Edit ONLY
`app/shared/design/analog-tokens.json`, then run
`node app/shared/design/generate.mjs`. Adding an `*Ease` token also requires
adding the curve to the `curves` map in `analog_tokens_parity_test.dart` AND to
`OVERSHOOT_ALLOWED` in `app/client/src/design/tokenParity.test.ts` if it
overshoots.

**Motion contract:** *things with mass overshoot, chrome does not.* `settleEase`
is the single allowed overshooting curve, and the web parity test enforces that
by name.

**One dropdown.** `showAnalogSelect` (`lib/analog/chrome/analog_select.dart`) is
the app's only picker. No surface has its own menu implementation any more —
keep it that way.

**One tray.** `IconTray` + `TrayButton` (`lib/ui/widgets/icon_tray.dart`) backs
both the profile control and the popcorn control.

---

## 4. Traps, all hit for real

1. `NeverScrollableScrollPhysics` does NOT remove a scrollbar. Physics governs
   input; the bar is added by the desktop `ScrollBehavior` and paints whenever
   content exceeds the viewport. Two switches — see `_NoScrollbar`.
2. An overflowing `Column` does not clip, it **throws**.
   `detail_screen_layout_test` guards this.
3. `Uri.replace(port: 443).toString()` on an https URI **normalises the port
   away**. A fix using it is a silent no-op.
4. `socket_io_client` parses a multi-label HTTPS host as **port 0**. Setting
   `port` in the options map does not help — the library builds the URL from
   the URL. `socketUrlFor` writes it into the URL.
5. Jellyfin puts an episode's still on **`Primary`**, not `Thumb`. Asking for
   Thumb 404s on every episode.
6. dio **throws** on non-2xx by default, so `response.statusCode == 404` is
   never reached. Catch `DioException` too.
7. Never render an indeterminate `CircularProgressIndicator` in persistent
   chrome — it never settles and hangs `pumpAndSettle`.
8. Nested wheel `Listener`s both receive the signal (double-step). The seasons
   column deliberately no longer takes the wheel.
9. A trackpad two-finger swipe is **pan-zoom**, not a scroll event. All seven
   surfaces now handle both; a new one must too.
10. `Border` on `BoxShape.circle` must be uniform or it throws every frame.
11. A dialog outlives its own `pop()` by the exit transition — a controller the
    caller disposes right after `await` is still being rebuilt.

---

## 5. Outstanding

**Asked for, not done:**
- **Unread badge / notifications outside the player.** Chat toasts exist ONLY
  over the player. Nothing tells you about a message while browsing.
- **The profile avatar's red dot is hardcoded** — it renders unconditionally,
  driven by nothing. It looks like an unread indicator and is not one.
- **Profile and watch-party editors** — "polished and minimal", never touched.

**Known regression, introduced deliberately:**
- Merging the Shows work removed the `/detail/:id` series interception, so
  **Sonarr's per-season / per-episode / whole-series download actions are gone
  from a library show's page.** Still reachable from Discover. Restoring them
  means porting those actions onto `DetailStage`, not reinstating the intercept.

**Investigated and NOT a bug** (do not "fix" it):
- Episode numbers with gaps (E5, E7, E11…) and missing seasons. The whole path
  — Jellyfin → server → client → rail — is a 1:1 map with no filter, dedup or
  limit. The library genuinely has those items only.

**Parity gap worth considering:** the web client falls back
*own Primary → series Primary → placeholder* for artwork; the native app has no
fallback and shows a bare placeholder.

---

## 6. How the user works

Fast, visual, iterative. Screenshots at `~/projects/*.png` — **read them off
disk**, and check the file, because a pair has twice been byte-identical.

They will tell you when a diagnosis is wrong, and they are usually right. The
scroll/clip problem was solved by their suggestion (scale the copy) after two
wrong answers. When they say "you decide", pick the highest-value item and act.

Say plainly when something is unverified. Several things this session were
claimed green before the run finished; that costs more trust than the bug did.
