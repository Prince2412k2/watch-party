import { useEffect, useState } from 'react'
import '../pages/servarr.css'

interface Device { id: string; name: string; expiresAt: number }

export default function ExtensionConnect() {
  const [code, setCode] = useState('')
  const [expiresAt, setExpiresAt] = useState(0)
  const [devices, setDevices] = useState<Device[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function loadDevices() {
    const response = await fetch('/api/extension/devices', { credentials: 'include' })
    if (!response.ok) throw new Error('Could not load paired extensions')
    setDevices(await response.json())
  }
  useEffect(() => { void loadDevices().catch(error => setError(error.message)) }, [])
  async function generate() {
    setBusy(true); setError('')
    try {
      const response = await fetch('/api/extension/pair-code', { method: 'POST', credentials: 'include' })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || 'Could not create a pairing code')
      setCode(data.code); setExpiresAt(data.expiresAt)
      await loadDevices()
    } catch (error) { setError(error instanceof Error ? error.message : 'Pairing failed') }
    finally { setBusy(false) }
  }
  async function revoke(id: string) {
    try {
      const response = await fetch(`/api/extension/devices/${id}`, { method: 'DELETE', credentials: 'include' })
      if (!response.ok) throw new Error('Could not revoke extension')
      await loadDevices()
    } catch (error) { setError(error instanceof Error ? error.message : 'Could not revoke extension') }
  }
  return <div className="sb-page"><header className="sb-header"><a className="sb-brand" href="/movies">Watch Party</a><a href="/profile">Profile</a></header><main className="sb-main" style={{ maxWidth: 820 }}>
    <div className="sb-heading"><div><p className="sb-eyebrow">WATCH PARTY FOR YOUTUBE</p><h1>Your room. Any YouTube video.</h1><p>Synced playback, chat, and floating camera feeds on YouTube.</p></div></div>
    <section><h2>Pair your browser</h2><a className="sb-button" href="/api/extension/download">Download extension</a><ol style={{ lineHeight: 1.9, paddingLeft: 20 }}><li>Extract the ZIP. Open <strong>chrome://extensions</strong> (or <strong>edge://extensions</strong>), enable Developer mode, and use <strong>Load unpacked</strong> to select the extracted folder. Chrome/Edge 133 or newer is required.</li><li>Open its toolbar popup and enter this server: <strong>{window.location.origin}</strong>.</li><li>Generate a code below and paste it into the extension.</li><li>Open a YouTube video. Start a party, or join with a room code.</li></ol>
      <button className="sb-button" disabled={busy} onClick={generate}>{busy ? 'Generating…' : 'Generate pairing code'}</button>
      {code && <div style={{ margin: '24px 0', padding: 20, border: '1px solid var(--sb-line)', borderRadius: 12 }}><label htmlFor="extension-code">One-use code · expires at {new Date(expiresAt).toLocaleTimeString()}</label><input id="extension-code" readOnly value={code} onFocus={event => event.target.select()} style={{ display: 'block', width: '100%', fontSize: 22, letterSpacing: '.08em', padding: 12, marginTop: 10, color: 'var(--sb-ink)', background: 'var(--sb-surface)', border: '1px solid var(--sb-line)', borderRadius: 8 }} /></div>}
      {error && <p role="alert">{error}</p>}
    </section>
    <section style={{ marginTop: 40 }}><h2>Paired extensions</h2><button className="sb-button" onClick={() => void loadDevices().catch(error => setError(error.message))}>Refresh devices</button>{devices.length ? devices.map(device => <div key={device.id} style={{ display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center', padding: '16px 0', borderBottom: '1px solid var(--sb-line)' }}><span>{device.name}<small style={{ display: 'block', color: 'var(--sb-muted)' }}>Expires {new Date(device.expiresAt).toLocaleDateString()}</small></span><button className="sb-button" onClick={() => void revoke(device.id)}>Revoke</button></div>) : <p>No active extensions paired yet.</p>}</section>
  </main></div>
}
