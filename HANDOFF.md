# Watchparty App — Claude Code Handoff Document

## What We're Building

A self-hosted watch party web app that lets users watch media together from a Jellyfin server, with live video chat, floating resizable camera tiles, a sidebar chat, and a host-controlled sync engine. Think Discord Stage + Netflix Party but fully self-hosted.

---

## Stack

| Service | Role |
|---|---|
| Jellyfin | Media server + user authentication |
| LiveKit | WebRTC video/audio (camera streams) |
| Coturn | TURN server for NAT traversal |
| Node.js + Socket.io | App server, session management, SyncPlay bridge |
| React | Frontend |
| HLS.js / Vidstack | Video player |
| react-rnd | Draggable/resizable floating camera tiles |

---

## Docker Compose Layout

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin
    ports:
      - "8096:8096"
    volumes:
      - ./jellyfin/config:/config
      - ./media:/media

  livekit:
    image: livekit/livekit-server
    ports:
      - "7880:7880"
      - "7881:7881"
      - "50000-50020:50000-50020/udp"
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml

  coturn:
    image: coturn/coturn
    network_mode: host
    volumes:
      - ./coturn.conf:/etc/coturn/turnserver.conf

  watchparty:
    build: ./app
    ports:
      - "3000:3000"
    environment:
      - JELLYFIN_URL=http://jellyfin:8096
      - LIVEKIT_URL=ws://livekit:7880
      - TURN_URL=turn:YOUR_PUBLIC_IP:3478
      - LIVEKIT_API_KEY=xxx
      - LIVEKIT_API_SECRET=xxx
      - TURN_USERNAME=xxx
      - TURN_PASSWORD=xxx
    depends_on:
      - jellyfin
      - livekit
      - coturn
```

**Note:** Stack assumes a public IP on the host machine. Coturn uses `network_mode: host` — this is required for TURN to work correctly.

---

## Project File Structure

```
watchparty/
├── docker-compose.yml
├── livekit.yaml
├── coturn.conf
└── app/
    ├── package.json
    ├── server/
    │   ├── index.js           ← Express + Socket.io entry
    │   ├── auth.js            ← Jellyfin auth proxy
    │   ├── session.js         ← Party session management
    │   ├── syncplay.js        ← Jellyfin SyncPlay API bridge
    │   └── livekit.js         ← LiveKit token generation
    └── client/
        ├── src/
        │   ├── App.jsx
        │   ├── pages/
        │   │   ├── Login.jsx         ← Jellyfin credentials login
        │   │   ├── Library.jsx       ← Jellyfin media browser
        │   │   ├── Lobby.jsx         ← Waiting room
        │   │   └── Party.jsx         ← Main watch room
        │   ├── components/
        │   │   ├── Player.jsx        ← Vidstack + SyncPlay hooks
        │   │   ├── CameraGrid.jsx    ← Floating tiles (react-rnd)
        │   │   ├── CameraTile.jsx    ← Single user camera
        │   │   ├── Dock.jsx          ← Meet/Zoom layout mode
        │   │   ├── Chat.jsx          ← Sidebar chat
        │   │   └── WaitingRoom.jsx   ← Host approval UI
        │   ├── hooks/
        │   │   ├── useSocket.js
        │   │   ├── useSyncPlay.js
        │   │   └── useLiveKit.js
        │   └── context/
        │       ├── AuthContext.jsx
        │       └── PartyContext.jsx
```

---

## Authentication

**Jellyfin is the only auth system. No separate accounts.**

Login flow:
```
User enters Jellyfin username + password
  ↓
POST /Users/AuthenticateByName to Jellyfin
  ↓
Returns { AccessToken, User: { Id, Name, IsAdministrator } }
  ↓
Store token in session (httpOnly cookie)
  ↓
All subsequent Jellyfin API calls use this token
```

Your app proxies this through its own `/api/auth/login` endpoint so the client never talks to Jellyfin directly for auth.

`IsAdministrator` from Jellyfin can be used to determine who can create parties (optional — you may want any user to be able to host).

---

## Party / Session Model

```js
session = {
  id: "abc123",              // room code
  hostId: "jellyfin-user-id",
  syncPlayGroupId: null,     // assigned after SyncPlay group created
  mediaItemId: null,         // Jellyfin item being watched
  guests: [],                // approved participants
  waiting: [],               // pending approval
  layoutMode: "float",       // "float" | "dock"
  collaborativeControl: false // if true, guests can also play/pause
}
```

Sessions live in memory on the server. They persist indefinitely until explicitly closed by the host or server restart.

---

## Host vs Guest Permissions

| Action | Guest | Host |
|---|---|---|
| Play / Pause | ✗ (✓ if collaborative mode) | ✓ |
| Seek | ✗ | ✓ |
| Kick user | ✗ | ✓ |
| Accept waiting room | ✗ | ✓ |
| Remove camera (others) | ✗ | ✓ |
| Hide camera (own view) | ✓ | ✓ |
| Transfer host | ✗ | ✓ |
| Toggle collaborative mode | ✗ | ✓ |
| Chat | ✓ | ✓ |

---

## Waiting Room Flow

```
Guest navigates to party link
  ↓
Server checks Jellyfin token (must be valid)
  ↓
Added to session.waiting[]
  ↓
Host receives Socket.io event: "user:waiting" { userId, name }
  ↓
Host approves or rejects
  ↓
approve → moved to session.guests[], "user:approved" event sent
reject  → socket disconnected, "user:rejected" event sent
```

---

## Media Sync — Jellyfin SyncPlay

**Do not build a custom sync engine. Use Jellyfin's SyncPlay API.**

Jellyfin SyncPlay is built into the server since v10.6.0. It handles:
- Master clock with NTP-style offset correction per client
- Play / pause / seek coordination
- Buffering detection — pauses group when someone is buffering (GroupWait)
- Speed adjustment (SpeedToSync) and seeking (SkipToSync) to recover drift

### Key SyncPlay API Endpoints

```
POST /SyncPlay/New                    ← host creates group
POST /SyncPlay/Join { GroupId }       ← guests join
POST /SyncPlay/Leave                  ← leave group
POST /SyncPlay/Play { ItemId }        ← start playing item
POST /SyncPlay/Pause                  ← pause for group
POST /SyncPlay/Unpause                ← resume for group
POST /SyncPlay/Seek { PositionTicks } ← seek (host only)
GET  /SyncPlay/List                   ← list active groups
```

All requests use the user's Jellyfin `AccessToken` as `X-Emby-Token` header.

### SyncPlay WebSocket Events

Jellyfin pushes sync commands over its existing WebSocket connection (`/socket`). Listen for:
- `SyncPlayCommand` — play, pause, seek instructions
- `SyncPlayGroupUpdate` — group state changes
- `SyncPlayUserJoined` / `SyncPlayUserLeft`

Your app server bridges these events to your own Socket.io rooms so the React client only talks to one WebSocket.

---

## Video Player

Use **Vidstack** (React-first, clean API, great HLS support).

```jsx
import { MediaPlayer, MediaProvider } from '@vidstack/react'

<MediaPlayer src={jellyfinHlsUrl}>
  <MediaProvider />
</MediaPlayer>
```

Jellyfin HLS stream URL format:
```
http://JELLYFIN_HOST:8096/Videos/{ItemId}/master.m3u8?api_key={AccessToken}
```

Player control hooks needed:
- Listen to SyncPlay commands → call `player.play()`, `player.pause()`, `player.currentTime = x`
- Report buffering state back to SyncPlay via `POST /SyncPlay/BufferingDone` or `POST /SyncPlay/Ready`

---

## Camera Tiles — LiveKit + react-rnd

LiveKit React SDK gives you a stream per participant. Pass each into a tile:

```jsx
import { Rnd } from 'react-rnd'
import { useParticipants } from '@livekit/components-react'

function FloatingCameras() {
  const participants = useParticipants()
  return participants.map(p => (
    <Rnd key={p.identity} default={{ x: 100, y: 100, width: 200, height: 150 }}>
      <CameraTile participant={p} />
    </Rnd>
  ))
}
```

**Hide/remove logic:**
- Hide = local React state only, just unmounts the tile for that viewer
- Remove (host kicking camera) = host emits `camera:remove { userId }` Socket.io event, server broadcasts, that user's tile is hidden for everyone

**Layout modes:**
- `float` — tiles are `<Rnd>` positioned absolutely over the video
- `dock` — tiles are in a `flex-row` strip above or beside the video, video resizes to fit

One state variable `layoutMode` switches rendering path. Per-user preference, persisted in localStorage.

---

## LiveKit Token Generation (Server Side)

```js
import { AccessToken } from 'livekit-server-sdk'

function generateLiveKitToken(userId, roomId) {
  const token = new AccessToken(
    process.env.LIVEKIT_API_KEY,
    process.env.LIVEKIT_API_SECRET,
    { identity: userId }
  )
  token.addGrant({ roomJoin: true, room: roomId })
  return token.toJwt()
}
```

Clients request a token from your server via `/api/livekit/token`, then connect to LiveKit directly. Your server never proxies media.

---

## Socket.io Event Map

### Client → Server
```
auth:login          { jellyfinToken }
party:create        { mediaItemId }
party:join          { partyId }
party:approve       { userId }
party:reject        { userId }
party:kick          { userId }
sync:play
sync:pause
sync:seek           { positionTicks }
chat:message        { text }
camera:hide         { userId }   ← local only, no server needed
camera:remove       { userId }   ← host only, server broadcasts
layout:change       { mode }     ← "float" | "dock"
```

### Server → Client
```
party:waiting       { user }           ← host gets this
party:approved      {}                 ← guest gets this
party:rejected      {}                 ← guest gets this
party:kicked        { userId }
party:state         { full session }   ← on join
sync:command        { type, data }     ← forwarded from SyncPlay WS
chat:message        { userId, name, text, timestamp }
user:joined         { userId, name }
user:left           { userId, name }
```

---

## Chat

Simple Socket.io message buffer on the server:

```js
session.messages = []   // in-memory, max 200 messages

socket.on('chat:message', ({ text }) => {
  const msg = { userId, name, text, timestamp: Date.now() }
  session.messages.push(msg)
  if (session.messages.length > 200) session.messages.shift()
  io.to(session.id).emit('chat:message', msg)
})

// On join, send history
socket.emit('chat:history', session.messages)
```

---

## Host Disconnect / Rejoin

```
Host disconnects
  ↓
Server starts 30s grace timer
  ↓
Session pauses (SyncPlay pause broadcast)
  ↓
If host rejoins within 30s → restore host, resume
If timer expires → promote first guest in guests[] by join time
If original host rejoins after promotion → they join as guest
```

Rule: **server always assigns host. Clients never self-promote.**

---

## Jellyfin Library Browser

Use Jellyfin's Items API:

```
GET /Items?userId={userId}&includeItemTypes=Movie,Series&recursive=true
GET /Items/{itemId}/Children    ← for series seasons/episodes
GET /Items/{itemId}/Images/Primary?maxHeight=300   ← poster art
```

Build a simple grid browser inside the app. Host picks media → triggers party creation with that `ItemId`.

---

## Build Order (Recommended)

1. **Docker Compose** — get all services running, verify Jellyfin accessible
2. **Auth** — login page, Jellyfin proxy, session cookie
3. **Library browser** — browse and pick media
4. **Party creation + waiting room** — Socket.io session, host approval flow
5. **Video player + SyncPlay** — Vidstack + SyncPlay API integration
6. **LiveKit cameras** — token generation, floating tiles with react-rnd
7. **Chat sidebar**
8. **Dock layout mode**
9. **Host controls UI** — kick, approve, transfer, collaborative toggle
10. **Polish** — transitions, mobile-ish layout, error states

---

## Key Dependencies

```json
{
  "server": {
    "express": "^4",
    "socket.io": "^4",
    "livekit-server-sdk": "^2",
    "node-fetch": "^3"
  },
  "client": {
    "react": "^18",
    "socket.io-client": "^4",
    "@livekit/components-react": "latest",
    "@vidstack/react": "latest",
    "react-rnd": "^10",
    "hls.js": "^1"
  }
}
```

---

## Known Gotchas

- **Coturn needs `network_mode: host`** — bridge networking breaks TURN
- **Jellyfin WebSocket needs proxy_pass upgrade headers** if behind Nginx — without this SyncPlay silently fails
- **SyncPlay PositionTicks** — Jellyfin uses ticks (1 tick = 100 nanoseconds), not seconds. Convert: `seconds * 10_000_000`
- **LiveKit UDP ports** — the `50000-50020` range must be open on your firewall/security group
- **Vidstack** needs `@vidstack/react` and its CSS imported separately
- **react-rnd** tiles need `position: absolute` on their parent container and `pointer-events: none` on the video underneath so clicks pass through to tiles correctly

---

## What's NOT In Scope (Yet)

- Mobile support
- Recording
- Screen share (LiveKit supports it, just not wired up)
- Persistent party history / database
- Multiple simultaneous parties per user
