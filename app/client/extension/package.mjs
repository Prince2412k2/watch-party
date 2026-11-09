import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { zipSync } from 'fflate'

const root = fileURLToPath(new URL('./dist/', import.meta.url))
const files = {}
function collect(directory, prefix = '') {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name)
    const name = `${prefix}${entry.name}`
    if (entry.isDirectory()) collect(path, `${name}/`)
    else files[name] = readFileSync(path)
  }
}
collect(root)
writeFileSync(new URL('./watchparty-youtube.zip', import.meta.url), zipSync(files, { level: 6 }))
console.log(`Packaged ${Object.keys(files).length} extension files as extension/watchparty-youtube.zip`)
