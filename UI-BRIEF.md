# Watchparty — UI Functional Brief (for Mockups)

> **For the designer.** This describes WHAT each screen contains and HOW it
> behaves — not how it should look. Every layout, color, type, spacing, and
> visual treatment decision is yours. Where we say "a control" or "a list," you
> decide the form (button, icon, menu, etc.).
>
> The product: a self-hosted "watch party" — a group watches a movie/show
> together in perfect sync, with their webcams visible as floating or docked
> tiles and a live text chat. One person is the **Host** (controls playback and
> who's allowed in); everyone else is a **Guest**.

---

## Roles (affects what UI a person sees)

- **Host** — created the party. Controls play/pause/seek, approves who enters,
  can kick people, remove others' cameras, hand off host role, toggle whether
  guests can also control playback.
- **Guest** — watches in sync. Can chat, toggle their own camera/mic, hide
  others' cameras locally, change their own layout. Cannot control playback
  (unless the host turns on "collaborative" mode).
- **Waiting** — a person who opened a party link but the host hasn't let in yet.

The same screens render differently per role. Call out host-only elements in mockups.

---

## Screen 1 — Login

**Purpose:** Authenticate with the Jellyfin media server (the only login system).

**Contains:**
- App name / branding area
- Username field
- Password field
- "Log in" action
- Error message area (e.g. "Invalid username or password," "Server unreachable")

**States:**
- Default (empty form)
- Submitting (in-progress / loading)
- Error (bad credentials or server down)

**After success:** goes to the Library screen.

---

## Screen 2 — Library (browse & pick what to watch)

**Purpose:** The host browses their media and starts a party. (Guests don't
normally see this — they arrive via a party link.)

**Contains:**
- A browsable grid of media items, each showing **poster art + title** (+ year
  if available)
- Item types: **Movies** and **Series**
- For a **Series**: selecting it drills into **Seasons → Episodes**
- A way to go back up (series → library)
- Per item (or on selecting it): a **"Start watch party"** action
- Possibly: search / filter (nice-to-have, not required for v1)

**States:**
- Loading (fetching library)
- Loaded grid
- Empty ("No media found")
- Drilled-in view (inside a series)

**On "Start watch party":** creates the party and goes to the Party screen as Host.

---

## Screen 3 — Waiting Room (guest, pre-approval)

**Purpose:** What a guest sees after opening a party link, before the host lets
them in.

**Contains:**
- A message like "Waiting for the host to let you in…"
- Possibly the party/media name
- A way to leave/cancel

**States:**
- Waiting (default)
- Approved → transitions into the Party screen
- Rejected → message "The host declined your request" + exit

---

## Screen 4 — Party Room (THE main screen)

This is where everything happens. It has many parts; mock the **Host view** and
the **Guest view** (they differ).

### 4A. Video player (center / primary area)
- Plays the movie/show, **synced for everyone**
- **Host** sees working transport controls: play/pause, seek/scrub bar, current
  time / duration, volume, fullscreen
- **Guest** sees the same video but playback controls are **read-only / disabled**
  (they can still do volume + fullscreen locally)
- **Exception:** if the host enables "collaborative control," guests' play/pause
  becomes active too
- A **buffering / loading** indicator (the group auto-pauses if someone is buffering)

### 4B. Camera tiles (participants' webcams)
Two layout modes the user can switch between (per-person preference):

- **Float mode** — each participant's camera is a small **draggable, resizable
  tile floating on top of the video**. User can move/resize freely.
- **Dock mode** — cameras line up in a **strip** (row or column) outside the
  video; the video resizes to fit the remaining space.

Per camera tile:
- Live webcam video + the person's **name**
- **Mic/speaking indicator** (e.g. shows who's talking, muted state)
- **Hide** control (hides that tile **just for me** — local only)
- **Host-only:** **Remove camera** control (turns off that person's camera **for
  everyone**)

Own camera controls (for every user, about themselves):
- Toggle **my camera** on/off
- Toggle **my mic** on/off

**States to mock:** no cameras yet, 1 camera, several cameras (e.g. 4–6),
a tile being dragged, a muted tile, a hidden tile.

### 4C. Chat (sidebar / panel)
- Scrollable **message list**: each message shows sender name + text (+ time)
- **Message input** + send
- Loads **history** when you join
- Should be **collapsible / toggleable** (so it can get out of the way)

**States:** empty chat, with messages, input focused.

### 4D. Layout / view controls
- A control to switch **Float ↔ Dock** camera layout
- A control to **show/hide chat**
- A control to toggle **my camera** and **my mic**

### 4E. Host control panel (HOST ONLY)
A place (panel, menu, or bar — your call) with:
- **Waiting list** — people requesting to join, each with **Approve** / **Reject**
  (this should be noticeable when someone is waiting — e.g. a badge/notification)
- **Participant list** — everyone in the party, each with host actions:
  - **Kick** (remove from party)
  - **Remove their camera**
  - **Make host** (transfer host role)
- **Collaborative control** toggle — "let guests control playback" on/off
- **Party info** — room link/code to share, what's playing

### 4F. Participant presence
- Some indication of **who's in the room** and a count
- **Join / leave** moments could surface (e.g. "Alice joined") — subtle

---

## Cross-cutting states & moments (please mock or note)

- **Notifications / toasts** — "Someone wants to join," "You were made host,"
  "Host disconnected — playback paused," "You were removed from the party."
- **Host disconnected** — if the host drops, the group sees a paused state with a
  message; after a short grace period a guest is auto-promoted to host (the new
  host then sees the host controls appear).
- **Connection lost / reconnecting** — for the user's own network dropping.
- **Empty / first-load** states for library, chat, and camera area.
- **Error states** — login failure, party not found, kicked/rejected.

---

## Notification badge priorities (what should grab attention)
1. Someone is **waiting** for host approval (host only) — highest
2. You were **made host** / **kicked** / **rejected**
3. New **chat message** when chat is collapsed
4. Someone **joined/left** — lowest, subtle

---

## Device scope
- **Desktop-first.** Mobile is explicitly out of scope for v1 (don't spend effort
  on phone layouts yet).

---

## What the designer does NOT need to worry about
- How sync works under the hood (it just works — design the play/pause/scrub UI)
- Auth mechanics (just the login form + error states)
- Where video/camera streams come from (treat them as video feeds)

---

## Screen inventory checklist (for mockups)
- [ ] Login (default / loading / error)
- [ ] Library grid (loading / loaded / empty / inside-a-series)
- [ ] Waiting room (waiting / rejected)
- [ ] Party — **Guest view**, Float layout
- [ ] Party — **Guest view**, Dock layout
- [ ] Party — **Host view** (with host control panel + waiting list)
- [ ] Camera tile — states (normal / speaking / muted / dragging / host-remove)
- [ ] Chat panel — open & collapsed
- [ ] Notifications / toasts
- [ ] Host-disconnected / reconnecting states
- [ ] Error states (party not found, kicked, rejected)
```
