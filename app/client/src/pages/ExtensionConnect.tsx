import { useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext.tsx'
import './servarr.css'

interface Device { id: string; name: string; expiresAt: number }

export default function ExtensionConnect() {
  const { user } = useAuth()
  const [devices, setDevices] = useState<Device[]>([])
  const [error, setError] = useState('')
  async function loadDevices() {
    const response = await fetch('/api/extension/devices', { credentials: 'include' })
    if (!response.ok) throw new Error('Could not load saved extension logins')
    setDevices(await response.json())
  }
  useEffect(() => { if (user) void loadDevices().catch(error => setError(error.message)) }, [user?.userId])
  async function revoke(id: string) {
    try {
      const response = await fetch(`/api/extension/devices/${id}`, { method: 'DELETE', credentials: 'include' })
      if (!response.ok) throw new Error('Could not revoke extension login')
      await loadDevices()
    } catch (error) { setError(error instanceof Error ? error.message : 'Could not revoke extension login') }
  }
  return <div className="sb-page"><header className="sb-header"><a className="sb-brand" href="/movies">Watch Party</a>{user && <a href="/profile">Profile</a>}</header><main className="sb-main" style={{ maxWidth: 820 }}>
    <div className="sb-heading"><div><p className="sb-eyebrow">WATCH PARTY FOR YOUTUBE · V0.3</p><h1>YouTube extension</h1><p>Synced playback, chat, and floating cameras.</p></div></div>
    <section><h2>Install and set up once</h2><a className="sb-button" href="/api/extension/download">Download extension</a><ol style={{ lineHeight: 1.9, paddingLeft: 20 }}>
      <li>Extract the ZIP. Open <strong>chrome://extensions</strong> or <strong>edge://extensions</strong>, enable Developer mode, and use <strong>Load unpacked</strong> to select the extracted folder. Chrome/Edge 133+ is required.</li>
      <li>Open Settings in the extension. Enter <strong>{window.location.origin}</strong> and your name.</li>
      <li>Hosts can add their admin username/password. Click <strong>Validate & save</strong>. Invalid settings are not saved.</li>
    </ol></section>
    <section style={{ marginTop: 32 }}><h2>Host a party</h2><p style={{ lineHeight: 1.8 }}>Click <strong>Create code</strong> in the extension. Share the code. The existing YouTube tab connects automatically; pages and videos follow for guests.</p></section>
    <section style={{ marginTop: 32 }}><h2>Join with a code</h2><p style={{ lineHeight: 1.8 }}>Enter the code and click <strong>Join</strong>.</p></section>
    <section style={{ marginTop: 32 }}><h2>Float your friends. Share control.</h2><p style={{ lineHeight: 1.8 }}>Enable your camera or mic. Each person gets a separate floating screen you can drag, resize, or collapse to an avatar, including in fullscreen. The host can use <strong>People → Give control</strong> for individual guests and revoke it at any time.</p></section>
    {user && <section style={{ marginTop: 40 }}><h2>Saved extension logins</h2><button className="sb-button" onClick={() => void loadDevices().catch(error => setError(error.message))}>Refresh devices</button>{devices.map(device => <div key={device.id} style={{ display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center', padding: '16px 0', borderBottom: '1px solid var(--sb-line)' }}><span>{device.name}<small style={{ display: 'block', color: 'var(--sb-muted)' }}>Expires {new Date(device.expiresAt).toLocaleDateString()}</small></span><button className="sb-button" onClick={() => void revoke(device.id)}>Revoke</button></div>)}</section>}
    {error && <p role="alert">{error}</p>}
  </main></div>
}
