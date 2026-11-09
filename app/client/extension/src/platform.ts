export function deadline<T>(operation: Promise<T>, milliseconds = 8000, message = 'Extension did not respond. Reload it and try again.'): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(message)), milliseconds)
    operation.then(value => { clearTimeout(timer); resolve(value) }, error => { clearTimeout(timer); reject(error) })
  })
}

export async function rpc<T = Record<string, any>>(type: string, payload: Record<string, unknown> = {}, timeout = 8000): Promise<T> {
  const response = await deadline(Promise.resolve().then(() => chrome.runtime.sendMessage({ channel: 'watchparty', type, ...payload })), timeout)
  if (!response) throw new Error('Reload the extension and YouTube tab.')
  if (response.error) throw new Error(response.error)
  return response.value as T
}

export const localGet = <T = Record<string, unknown>>(keys: string | string[]) => rpc<T>('storage-get', { area: 'local', keys })
export const localSet = (value: Record<string, unknown>) => rpc('storage-set', { area: 'local', value })
export const localRemove = (keys: string | string[]) => rpc('storage-remove', { area: 'local', keys })
export const sessionGet = <T = Record<string, unknown>>(keys: string | string[]) => rpc<T>('storage-get', { area: 'session', keys })
export const sessionSet = (value: Record<string, unknown>) => rpc('storage-set', { area: 'session', value })
export const sessionRemove = (keys: string | string[]) => rpc('storage-remove', { area: 'session', keys })

export function observeStorage(callback: (changes: Record<string, chrome.storage.StorageChange>, area: string) => void) {
  let stopped = false
  let port: chrome.runtime.Port | undefined
  let retry: ReturnType<typeof setTimeout> | undefined
  const connect = () => {
    if (stopped) return
    try {
      port = chrome.runtime.connect({ name: 'watchparty-state' })
      port.onMessage.addListener(message => { if (message.type === 'storage') callback(message.changes, message.area) })
      port.onDisconnect.addListener(() => { if (!stopped) retry = setTimeout(connect, 1000) })
    } catch { if (!stopped) retry = setTimeout(connect, 1000) }
  }
  connect()
  const heartbeat = setInterval(() => { try { port?.postMessage({ type: 'ping' }) } catch {} }, 20_000)
  return () => { stopped = true; clearInterval(heartbeat); clearTimeout(retry); port?.disconnect() }
}
