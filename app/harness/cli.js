// Interactive REPL for driving the sync harness by hand.
//   WP_SERVER=http://localhost:3999 node harness/cli.js
//
// Commands:
//   host [mediaId]          create a party (this client becomes host)
//   join <code>             join a party by code
//   approve <userId>        (host) approve a waiting guest
//   play [sec]              author a play at the given (or current) second
//   pause                   author a pause
//   seek <sec>              author a seek
//   mode <hopping|dragging> switch sync mode
//   spawn-guest <name> [ms] spawn a local headless guest (optional send-delay ms)
//   status                  table of every local client's position/drift/rate
//   sessions                GET the server debug endpoint
//   quit

import readline from 'readline'
import { HeadlessClient } from './client.js'

const SERVER = process.env.WP_SERVER || 'http://localhost:3999'

const host = new HeadlessClient({ name: 'cli-host' })
const guests = []
const all = () => [host, ...guests]

host.onWaiting = ({ userId, name }) => {
  process.stdout.write(`\n[waiting] ${name} (${userId}) wants in — 'approve ${userId}'\n> `)
}

function table() {
  const rows = all().filter(c => c.socket).map(c => c.status())
  if (!rows.length) return '(no connected clients)'
  const cols = ['name', 'isHost', 'position', 'drift', 'rate', 'paused']
  const head = cols.map(c => c.padEnd(10)).join(' ')
  const body = rows.map(r => cols.map(c => String(r[c]).padEnd(10)).join(' ')).join('\n')
  return `${head}\n${body}`
}

async function sessions() {
  const res = await fetch(`${SERVER}/api/debug/sessions`)
  if (!res.ok) return `debug endpoint returned ${res.status} (WP_TEST_MODE not set?)`
  return JSON.stringify(await res.json(), null, 2)
}

async function main() {
  await host.login(SERVER)
  await host.connect()
  console.log(`connected as host "${host.name}" (${host.userId}) → ${SERVER}`)

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout, prompt: '> ' })
  rl.prompt()

  rl.on('line', async (line) => {
    const [cmd, ...args] = line.trim().split(/\s+/)
    try {
      switch (cmd) {
        case 'host': {
          const r = await host.createParty(args[0] || 'test-media')
          console.log('party:', r?.partyId || r?.error, '→ share this code with joiners')
          break
        }
        case 'join': {
          const r = await host.joinParty(args[0])
          console.log('join:', JSON.stringify(r))
          break
        }
        case 'approve': { console.log('approve:', JSON.stringify(await host.approve(args[0]))); break }
        case 'play': { host.play(args[0] != null ? Number(args[0]) : undefined); console.log('play sent'); break }
        case 'pause': { host.pause(); console.log('pause sent'); break }
        case 'seek': { host.seek(Number(args[0] || 0)); console.log('seek sent'); break }
        case 'mode': { console.log('mode:', JSON.stringify(await host.setSyncMode(args[0]))); break }
        case 'spawn-guest': {
          const name = args[0] || `guest-${guests.length + 1}`
          const delay = Number(args[1] || 0)
          const g = new HeadlessClient({ name, sendDelayMs: delay, scheduleDelayMs: delay })
          await g.login(SERVER)
          await g.connect()
          const jr = await g.joinParty(host.partyId)
          guests.push(g)
          if (jr?.status === 'waiting') {
            console.log(`${name} joined and is WAITING (userId ${g.userId}) — approve it`)
          } else {
            console.log(`${name} joined (userId ${g.userId})`)
          }
          break
        }
        case 'status': console.log(table()); break
        case 'sessions': console.log(await sessions()); break
        case 'quit': case 'exit': all().forEach(c => c.disconnect()); rl.close(); return process.exit(0)
        case '': break
        default: console.log(`unknown: ${cmd}`)
      }
    } catch (err) { console.log('error:', err.message) }
    rl.prompt()
  })

  rl.on('close', () => { all().forEach(c => c.disconnect()); process.exit(0) })
}

main().catch(err => { console.error(err); process.exit(1) })
