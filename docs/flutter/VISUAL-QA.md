# Watchparty Flutter — Visual QA Checklist

Run these when you're back at the machine (they need a display; I can't see pixels
over SSH/XWayland). Do them in order. Check each box; note anything off.

## Setup (once)
```bash
export PATH="$PATH:$HOME/flutter/bin"
# The dev backend must be running on :3005 (I keep it up; if not, see bottom).
cd ~/projects/watch_party/flutter_app
GDK_BACKEND=x11 DISPLAY=:0 ./build/linux/x64/release/bundle/watchparty
```
Log in with **root / root**. (If a build is newer, rebuild first: `flutter build linux`.)

---

## Wave 1 — shell, auth, design  (built, awaiting your eyes)

- [ ] **Login screen** renders: centered card, "Watchparty" wordmark, "Welcome
      back" / "Sign in with your Jellyfin account", username + password fields,
      a white primary "Sign in" button. Enter submits.
- [ ] **Login works**: root/root advances to the home shell (no error banner).
- [ ] **App shell**: left nav with Home / Browse / Party / Downloads / Offline /
      Find; clean active state (no boxed pill/glow); a flat title-bar row.
- [ ] **Design system** is cinematic-minimal: near-black surfaces, near-white
      text, ONE muted red only for danger/live, NO gradients, NO glass/blur.
- [ ] **Session persists**: quit (tray/close) and relaunch → goes straight to
      home, no re-login.
- [ ] **Design gallery** (optional): temporarily set `initialLocation` to
      `/gallery` in `lib/app/router.dart` (or navigate there) to see every widget
      + color swatches + type scale on one screen.

_Note: Browse / Party / Downloads / Offline / Find are placeholders in Wave 1 —
they get real screens in Wave 2 (below)._

---

## Wave 2 — library, player UI, A/V, chat, offline, servarr

**Library / browse / detail (E3):**
- [ ] **Home** shows rails (Continue Watching / Next Up / Libraries) with real
      posters from Jellyfin; clicking a poster opens detail.
- [ ] **Browse** (nav → Browse): search box filters results; All/Movies/Series
      chips work; poster grid loads.
- [ ] **Detail** screen: poster, title, metadata chips, overview, **Play** button.

**Playback (E4.2 over E4.1):**
- [ ] From a detail screen, **Play** opens the video full-screen and it plays
      (this is media_kit direct-play — the real movie, no transcode).
- [ ] **Transport bar**: play/pause, scrubber seeks, time shows, volume,
      playback-rate menu, audio/subtitle track menus, fullscreen. Auto-hides
      while playing, reappears on mouse move.
- [ ] **Keyboard**: space=play/pause, ←/→ ±5s, f=fullscreen, m=mute.

**Downloads / offline (E8):**
- [ ] Detail screen shows a **Download** button; starting it shows progress →
      flips to "Downloaded".
- [ ] **Downloads** screen lists active downloads with pause/resume/cancel.
- [ ] **Offline** screen lists downloaded titles; Play works **with the network
      backend stopped** (true offline).

**Find / servarr (E9):**
- [ ] **Find** screen (nav → Find): search a movie/show, see results/releases,
      request one. (Upstream *arr may be unreachable in this env — a graceful
      error is acceptable; the screen should render.)
- [ ] Servarr **queue** view (`/servarr/queue`) renders active acquisitions.

**A/V + chat (E6/E7 — components; full test is in Wave 3's party screen):**
- [ ] (Deferred to Wave 3 party screen) camera tiles + chat panel — the LiveKit
      spike already proved camera works; these get wired into the party UI next.

_Party screen (E5), which composes player + camera tiles + chat with live sync,
and packaging (E10) are Wave 3 — checklist items added when they land._

---

## If the backend isn't running
```bash
cd ~/projects/watch_party/app
SECRET=$(cat /tmp/wp-native-secret.txt)
PORT=3005 NODE_ENV=development JELLYFIN_URL=http://localhost:8096 \
  NATIVE_STREAM_SECRET="$SECRET" SESSION_STORE_DIR=/tmp/wp-native-sessions \
  LIVEKIT_PUBLIC_URL=ws://localhost:7880 npm start
```
(Login is rate-limited to 10 attempts / 5 min per IP+user; if you hit a 429, wait
5 min or restart the backend to clear it.)
