# Remote browser in watch parties

Status: draft (Phase 1 — spec)
Surface: Express server (`app/server`), web client (`app/client`), Flutter app (`flutter_app`)
Feasibility: established — see `docs/specs/2026-08-04-remote-browser-spike.md` (GO)

## Problem

A party can only watch what is in the Jellyfin library. Anything else — a YouTube video,
a clip someone linked in chat, a livestream — means everybody opens it separately and
tries to press play at the same time. There is no shared surface for content the library
does not hold.

A previous attempt (`feature/neko-collab-browser`, ~6,700 lines, unmerged) failed not on
the idea but on the transport: Neko owns its own WebRTC stack, so the integration grew a
proxy, a cookie relay, and finally a hand-ported remote-desktop client. The spike
established that a containerised Chromium can publish its screen into the LiveKit room
the app already runs, as an ordinary publish-only participant. That deletes the entire
client and proxy layer, and the Flutter app inherits the feature because it already
speaks LiveKit.

## User stories

### US-1 — Watch something that isn't in the library (P1)
As a host, I open a shared browser in my party, navigate to a video, and everyone in the
party sees and hears it at the same time.

*Independent test:* with two participants in a party, the host opens the shared browser,
navigates to a video URL, and the second participant sees the same frames and hears the
same audio without doing anything.

- **Given** I am the host of a party, **when** I start the shared browser, **then** every
  participant sees the browser's screen.
- **Given** the browser is showing a playing video, **when** another participant looks at
  it, **then** they see the same content and hear its audio.
- **Given** I navigate to a different page, **when** participants are watching, **then**
  they see the new page without reloading or rejoining.
- **Given** a participant joins the party after the browser has started, **when** they
  arrive, **then** they see the browser's current screen.

### US-2 — Drive it (P1)
As the driver, I click, scroll and type in the shared browser as though it were my own,
using its address bar and tabs.

*Independent test:* the driver types a URL into the browser's own address bar, presses
Enter, scrolls the page and clicks a link — every action takes effect and is visible to
other participants.

- **Given** I am the driver on a desktop, **when** I click in the stream, **then** the
  click lands at the point I aimed at.
- **Given** I am the driver, **when** I type, **then** the keystrokes reach the focused
  field in the remote page.
- **Given** I am the driver, **when** I scroll, **then** the remote page scrolls.
- **Given** I am not the driver, **when** I click or type on the stream, **then** nothing
  happens in the remote browser.
- **Given** I am moving the pointer continuously, **when** input is being sent, **then**
  the page I am using stays responsive.

### US-3 — Hand over control (P1)
As a guest, I ask for control of the browser, and the host decides.

*Independent test:* a guest requests control, the host sees the request and accepts, and
the guest's clicks then take effect while the host's no longer do.

- **Given** I am a guest, **when** I request control, **then** the host is notified.
- **Given** a guest has requested control, **when** I accept as host, **then** that guest
  becomes the only driver.
- **Given** a guest is driving, **when** I take control back as host, **then** their input
  stops taking effect and mine resumes.
- **Given** a guest is driving, **when** they leave the party, **then** control returns to
  the host rather than being stranded.
- **Given** I am a guest, **when** the host declines, **then** I am told, and I am not
  driving.

### US-4 — Watch from a phone (P2)
As a participant on a phone, I can watch the shared browser even though I cannot drive it.

*Independent test:* join a party from a phone while the browser is showing a playing
video; the video and audio arrive, and touching the stream changes nothing remotely.

- **Given** I am on a phone, **when** the browser is running, **then** I see and hear it.
- **Given** I am on a phone, **when** I touch or swipe the stream, **then** no input
  reaches the remote browser and my own scrolling still works.
- **Given** I am on a phone, **when** I look for a control affordance, **then** the UI
  tells me control requires a desktop rather than offering a button that does nothing.

### US-5 — Nothing leaks to the next party (P1)
As a user, whatever anyone signed into, downloaded, or installed in the shared browser is
gone before another party uses it.

*Independent test:* sign into a site in the shared browser, close the browser, start it
again from a different party, and confirm the session is not signed in.

- **Given** someone signed into a site, **when** the browser is closed, **then** a
  subsequent start is not signed in.
- **Given** someone downloaded a file or installed an extension, **when** the browser is
  closed, **then** neither is present on a subsequent start.
- **Given** a party ends without anyone closing the browser, **when** it is torn down,
  **then** the same wipe happens.

### US-6 — It costs nothing while unused (P2)
As the operator, the feature consumes almost no CPU when no party is using it, and comes
back quickly when one does.

*Independent test:* with the browser idle, sample container CPU; then start the browser
and time how long until content is streaming.

- **Given** no party is using the browser, **when** I measure CPU, **then** it is
  negligible.
- **Given** no party is using the browser, **when** a party starts it, **then** content is
  streaming within a few seconds.
- **Given** the browser is in use, **when** the party switches away or ends, **then** it
  returns to the idle state without operator action.

## Functional requirements

**Activity model**
- FR-001: A party MUST have exactly one current activity, one of: nothing, Jellyfin
  playback, or the shared browser. Starting the shared browser MUST stop Jellyfin
  playback for the party, and vice versa.
- FR-002: Only the host MUST be able to start or stop the shared browser for a party.
- FR-003: Party state sent to clients MUST carry which activity is current, so a client
  that reloads or joins late renders the right surface without guessing.
- FR-004: The shared browser MUST NOT use the Jellyfin playback sync engine. It is a live
  stream; all participants receive the same frames and there is nothing to synchronise.

**Presentation**
- FR-005: The browser's screen MUST reach participants as a video track in the party's
  existing LiveKit room, published by a participant identity distinguishable from human
  participants.
- FR-006: The browser's audio MUST reach participants as an audio track, independently
  volume-controllable from participants' voices.
- FR-007: The stream MUST include the browser's own tab strip and address bar, so the
  driver can use tabs and navigation directly.
- FR-008: Clients MUST render the stream without distorting its aspect ratio, and MUST
  make clear when the displayed size is not one-to-one with the remote screen, because
  any other scale resamples the image and makes text soft.
- FR-009: A surface that begins streaming without a user gesture MUST offer an explicit
  control to start audio, because browsers refuse audible autoplay and a silent stream is
  indistinguishable from a broken one.
- FR-010: Participants MUST be able to view the shared browser on desktop and on phone,
  and on both the web client and the Flutter app.

**Control**
- FR-011: At most one participant MUST hold control at any time.
- FR-012: The host MUST hold control by default when the browser starts.
- FR-013: A guest MUST be able to request control; the host MUST be able to accept or
  decline; and the host MUST be able to reclaim control at any time.
- FR-014: Control MUST return to the host if the current driver leaves the party or
  disconnects.
- FR-015: Input MUST be accepted only from the current driver. The server MUST enforce
  this; client-side gating alone is not sufficient.
- FR-016: Input MUST NOT be reachable except by an authenticated member of the party that
  currently owns the browser.
- FR-017: Control on phones MUST NOT be offered. Phones are view-only, and the UI MUST say
  so rather than present an affordance that does nothing.
- FR-018: Pointer, keyboard and scroll input MUST be delivered such that a continuously
  moving pointer cannot degrade the driver's own client. Superseded positions MUST be
  discarded rather than queued, and the number of requests in flight MUST be bounded.
- FR-019: Input coordinates MUST be translated from the displayed image to the remote
  screen, accounting for letterboxing, so a click lands where the driver aimed regardless
  of window size.

**Isolation**
- FR-020: Closing the browser MUST destroy its profile — cookies, history, downloads,
  extensions and signed-in sessions — before it can be started again.
- FR-021: Ending a party MUST close the browser and perform the same wipe, without relying
  on any client to ask for it.
- FR-022: The browser MUST NOT be able to reach the party's own media. It publishes only.

**Lifecycle and cost**
- FR-023: The browser container MUST remain resident between uses. Its supporting
  processes stay up; only the browser process is started and stopped.
- FR-024: While no party is using the browser, the system MUST NOT encode or transmit
  video or audio, and MUST NOT hold the browser process.
- FR-025: Returning from idle to streaming content MUST take no more than ~5 seconds.
- FR-026: The system MUST return to the idle state automatically when the owning party
  switches activity, ends, or loses all participants — with no operator action.
- FR-027: Exactly one party MUST be able to use the shared browser at a time. A second
  party's request MUST be refused rather than starting a second browser or silently joining
  the first. The refusal MUST say only that the browser is in use — it MUST NOT identify
  the occupying party, its host, or its participants, since that would reveal who is
  watching together.
- FR-028: Resource ceilings MUST be enforced on the container so it cannot starve the rest
  of the host, and MUST be set from measured usage rather than guessed.

**Feature flag**
- FR-029: The shared browser MUST be switchable on and off by deployment configuration,
  following the existing environment-variable convention used for `WP_TEST_MODE` and
  `SERVE_CLIENT`.
- FR-030: The flag MUST default to OFF, so a deployment that sets nothing behaves exactly
  as it does today.
- FR-031: With the flag off, the feature MUST be absent rather than merely hidden: no
  browser control appears in any client, the server MUST NOT expose the endpoints or socket
  events that drive it, and no container MUST be started. A request crafted by hand MUST be
  refused.
- FR-032: Turning the flag off MUST NOT require a data migration or leave a party stuck in
  the browser activity. Any party on that activity when the flag is turned off MUST fall
  back to no activity.
- FR-033: Clients MUST learn whether the feature is available from the server rather than
  their own build configuration, so one deployment's setting cannot be contradicted by a
  stale client bundle.

**Fault isolation**
- FR-034: Failure of the shared browser MUST NOT degrade Jellyfin playback, camera or
  microphone streams, chat, join and approval flows, or party creation and teardown.
- FR-035: A browser that fails to start, crashes, exits unexpectedly, or stops publishing
  MUST leave the party intact and usable, and MUST surface as an error on the browser
  surface only.
- FR-036: A party MUST be able to return to Jellyfin playback after any browser failure,
  without recreating the party or rejoining.
- FR-037: Errors originating in the browser subsystem MUST NOT propagate into party
  lifecycle handling. An unhandled failure there MUST NOT be able to crash the server
  process or abort an unrelated party operation.
- FR-038: The absence or unavailability of the container runtime MUST be treated as "the
  feature is unavailable", not as a server fault.
- FR-039: Browser traffic MUST be constrained so it cannot crowd out participants' camera
  and microphone streams, which share the same room and uplink.
- FR-040: If the browser cannot be torn down cleanly, the party MUST still be able to end,
  and the failure MUST be recorded for the operator rather than blocking the teardown.

## Success criteria

- SC-001: Two participants in one party see the same page within one second of each other,
  and both hear its audio.
- SC-002: A participant joining after the browser started sees the current screen without
  reloading.
- SC-003: A driver's click lands within 5 px of the intended point on the remote screen, at
  three window sizes including one where the stream is letterboxed on each axis.
- SC-004: A driver moving the pointer continuously for 30 seconds leaves their own client
  responsive and able to reload normally.
- SC-005: A non-driver's clicks and keystrokes produce no effect in the remote browser,
  verified with the server as the enforcement point.
- SC-006: Control transfers from host to an accepted guest and back, with only one driver
  effective at any moment.
- SC-007: When the driver disconnects, control is back with the host without intervention.
- SC-008: A site signed into before a close is not signed in after the next start.
- SC-009: An extension installed or file downloaded before a close is absent after the
  next start.
- SC-010: With no party using the browser, container CPU is under 5% of one core, and no
  video or audio is being transmitted.
- SC-011: From idle, content is streaming within 5 seconds of a party starting the browser.
- SC-012: A second party attempting to start the browser while it is in use is refused
  with a reason, and the first party's session is unaffected.
- SC-013: A phone participant sees and hears the browser, is not offered control, and
  their touches do not reach it.
- SC-014: The Flutter app renders the shared browser and its audio, using the same LiveKit
  room as the web client.
- SC-015: Ending a party leaves no browser process running and no profile data on disk.
- SC-016: Container CPU and memory stay within their configured ceilings while a video
  plays for ten minutes.
- SC-017: With the flag unset, the application behaves identically to before this feature:
  no browser affordance in any client, and the driving endpoints and socket events reject
  hand-crafted requests.
- SC-018: Turning the flag off while a party is on the browser activity leaves that party
  usable, on no activity, and able to start Jellyfin playback.
- SC-019: Killing the browser process mid-session leaves Jellyfin playback, cameras,
  microphones and chat working for every participant in that party, and the party can start
  Jellyfin playback afterwards.
- SC-020: With the container runtime unavailable, starting the browser reports the feature
  as unavailable, and every other party function continues to work.
- SC-021: A party unrelated to the one using the browser is unaffected by that browser
  failing, including its ability to start, play and end.
- SC-022: A browser that cannot be torn down does not prevent its party from ending.

## Out of scope

- **DRM content.** Netflix, Disney+ and Prime are assumed not to work: Widevine is L3-only
  in a container, streaming services reject datacenter IPs, and Chromium blanks protected
  content under screen capture regardless. YouTube is the acceptance bar and it works.
- **Control from phones.** Deliberate, per the interview. Accepted consequence: a party
  in which every participant is on a phone has nobody who can navigate, so at least one
  desktop participant is required to drive.
- **More than one party using a shared browser at once.** The measured allocation (4 of 8
  vCPUs) does not permit a second container.
- **1080p.** Not established at the chosen allocation — estimated 4–5.4 vCPU on prod and
  never validly measured. 720p is the shipping resolution.
- **Per-viewer quality adaptation (simulcast).** Off deliberately; encoding multiple layers
  of full-motion video is the largest avoidable CPU cost. Consequence: a viewer on a poor
  connection gets the full bitrate or nothing.
- **Restricting which sites can be visited.** No allow-list; the driver may go anywhere.
- **A cursor rendered from the remote screen.** Screen capture does not include the
  pointer; drawing it locally from the driver's own position is both cheaper and lower
  latency.
- **Saving anything from the browser.** Downloads land in a profile that is wiped.
- **Recording or replaying a browser session.**
- **Text or link sharing into the browser from chat.**

## Assumptions

- One shared browser instance for the whole deployment, not one per party. Forced by the
  measured cost: 4 vCPU each on an 8 vCPU host that also runs Jellyfin and the *arr stack.
  `app/server/neko/lease.js` already models a single instance with a single controller.
- 720p30 at a ~2.5 Mbps ceiling. Measured 68.6% of one core and 1.15 GiB while playing
  YouTube, with load spikes to ~160%; the 4 vCPU allocation covers both.
- The lifecycle modules from the unmerged branch — `lease.js`, `idle.js`, `teardown.js`,
  `detach.js`, `routes.js` (646 lines, 884 lines of tests) — are the right foundation and
  carry over. `proxy.js` does not: it existed only because Neko served its own client.
- Input rides the existing Socket.IO connection, which already carries party state and
  already knows who the host is. The spike's open HTTP endpoint was expedient and is not
  a candidate for production.
- The Flutter app needs no new transport. It already speaks LiveKit via `flutter_webrtc`,
  so viewing is track rendering, and it is view-only on phones by the decision above.
- Idle is defined by the owning party no longer being on the browser activity, not by
  absence of input. Input-based idling would close the browser during a long video, which
  is the main thing people will be doing.
- Egress, not CPU, is the scaling constraint. LiveKit is an SFU and sends one copy per
  subscriber, so a four-person party is ~2.4 Mbps in and ~10 Mbps out before cameras.
- Phones letterbox the 720p surface to fit and are expected to be used in landscape for
  this feature; no phone-specific remote resolution is attempted.
- Extensions remain available to the driver, since the interview chose full browser chrome
  and the profile wipe bounds the consequences.
- A corporate TLS-inspecting proxy can break HTTPS inside the container. Not a concern on
  the VPS, and the spike harness already supports trusting an extra CA if a developer
  hits it locally.

## Open questions

None. The one marker — how much to disclose when refusing a second party — was resolved to
"say only that it is in use" and is now FR-027. Everything else is recorded as an
assumption above.
