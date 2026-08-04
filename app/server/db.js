import { mkdirSync } from 'fs'
import { dirname, join } from 'path'
import { DatabaseSync } from 'node:sqlite'

// One handle for every durable table in the app. Parties were the first thing
// worth keeping across restarts and owned the connection; profiles are the
// second, and two DatabaseSync handles on one file is a worse answer than a
// shared one. Each store creates its own tables on import.
const databasePath = process.env.PARTY_DB_PATH
  || (process.env.WP_TEST_MODE === '1'
    ? join('/tmp', `watchparty-test-${process.pid}.sqlite`)
    : join(process.cwd(), 'data/watchparty.sqlite'))

mkdirSync(dirname(databasePath), { recursive: true })

export const db = new DatabaseSync(databasePath)
db.exec('PRAGMA journal_mode = WAL;')
