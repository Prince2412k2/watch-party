(() => {
  if (document.getElementById('watchparty-extension-root')) return
  const extensionOrigin = chrome.runtime.getURL('/').replace(/\/$/, '')
  const host = document.createElement('div')
  host.id = 'watchparty-extension-root'
  host.style.cssText = 'position:fixed;right:18px;bottom:18px;z-index:2147483647;color-scheme:dark;'
  const shadow = host.attachShadow({ mode: 'closed' })
  const style = document.createElement('style')
  style.textContent = `:host{font:13px system-ui,sans-serif;color:#eef2f3}button{font:inherit;color:inherit;background:#243039;border:1px solid #46535b;border-radius:7px;padding:8px 11px;cursor:pointer}button:focus-visible{outline:2px solid #98d3b9;outline-offset:2px}.launcher{box-shadow:0 5px 25px #0008}.panel{width:380px;height:min(740px,calc(100vh - 40px));min-width:300px;min-height:220px;max-width:calc(100vw - 20px);max-height:calc(100vh - 20px);resize:both;overflow:hidden;border:1px solid #46535b;border-radius:12px;background:#171d22;box-shadow:0 8px 40px #0007;display:flex;flex-direction:column}.bar{display:flex;align-items:center;gap:6px;padding:8px;background:#20282e;cursor:move;touch-action:none}.bar strong{flex:1;font-size:12px}.bar button{font-size:11px;padding:6px}iframe{display:block;flex:1;width:100%;min-height:0;border:0;background:#171d22}[hidden]{display:none!important}`
  const launcher = document.createElement('button')
  launcher.className = 'launcher'
  launcher.textContent = 'Watch Party'
  const panel = document.createElement('section')
  panel.className = 'panel'
  panel.setAttribute('aria-label', 'Watch Party overlay')
  panel.hidden = true
  const bar = document.createElement('div')
  bar.className = 'bar'
  const title = document.createElement('strong')
  title.textContent = 'Watch Party · drag to move'
  const fullscreen = document.createElement('button')
  fullscreen.textContent = 'Fullscreen'
  const hide = document.createElement('button')
  hide.textContent = 'Hide'
  hide.title = 'Hide overlay; your room stays connected'
  const frame = document.createElement('iframe')
  frame.src = chrome.runtime.getURL('index.html')
  frame.allow = 'camera; microphone; speaker-selection; autoplay; fullscreen'
  frame.title = 'Watch Party room, chat, and cameras'
  frame.referrerPolicy = 'no-referrer'
  bar.append(title, fullscreen, hide)
  panel.append(bar, frame)
  shadow.append(style, launcher, panel)
  document.documentElement.append(host)

  launcher.onclick = () => { panel.hidden = false; launcher.hidden = true; snapshot() }
  hide.onclick = () => { panel.hidden = true; launcher.hidden = false }
  async function toggleFullscreen() {
    try {
      if (document.fullscreenElement) await document.exitFullscreen()
      else await (document.querySelector('#movie_player') || document.documentElement).requestFullscreen()
    } catch (error) { send({ type: 'error', message: error.message || 'Fullscreen could not open' }) }
  }
  fullscreen.onclick = toggleFullscreen
  document.addEventListener('fullscreenchange', () => {
    // The overlay must be INSIDE the native fullscreen subtree to stay visible.
    // A normal append reloads nested iframes. Chrome 133+'s atomic move keeps
    // the socket, camera/mic tracks, and chat mounted through fullscreen.
    const target = document.fullscreenElement || document.documentElement
    if (target.moveBefore && host.isConnected) target.moveBefore(host, null)
    else target.append(host)
    host.style.left = ''; host.style.top = ''; host.style.right = '18px'; host.style.bottom = '18px'
  })
  let drag = null
  bar.addEventListener('pointerdown', event => {
    if (event.target.closest('button')) return
    const rect = host.getBoundingClientRect()
    drag = { x: event.clientX - rect.left, y: event.clientY - rect.top }
    bar.setPointerCapture(event.pointerId)
  })
  bar.addEventListener('pointermove', event => {
    if (!drag) return
    host.style.left = `${Math.max(0, Math.min(innerWidth - host.offsetWidth, event.clientX - drag.x))}px`
    host.style.top = `${Math.max(0, Math.min(innerHeight - 50, event.clientY - drag.y))}px`
    host.style.right = 'auto'; host.style.bottom = 'auto'
  })
  bar.addEventListener('pointerup', () => { drag = null })
  bar.addEventListener('pointercancel', () => { drag = null })

  const send = data => frame.contentWindow?.postMessage({ source: 'watchparty-youtube', ...data }, extensionOrigin)
  let video = null
  let gestureUntil = 0
  let applyingUntil = 0
  let seekingUntil = 0
  const adPlaying = () => !!document.querySelector('#movie_player.ad-showing, #movie_player.ad-interrupting')
  const videoId = () => new URL(location.href).searchParams.get('v')
  for (const name of ['pointerdown', 'keydown']) document.addEventListener(name, event => {
    if (!event.isTrusted || event.target === host) return
    const inPlayer = document.querySelector('#movie_player')?.contains(event.target)
    if (name === 'keydown') {
      if (['INPUT', 'TEXTAREA', 'SELECT'].includes(event.target.tagName) || event.target.isContentEditable || event.ctrlKey || event.metaKey || event.altKey) return
      const playbackKey = [' ', 'k', 'K', 'j', 'J', 'l', 'L', 'ArrowLeft', 'ArrowRight', 'Home', 'End', '<', '>'].includes(event.key) || /^[0-9]$/.test(event.key)
      if (!inPlayer && !playbackKey) return
    } else if (!inPlayer) return
    gestureUntil = Date.now() + 1800
  }, true)

  function localEvent(event) {
    if (!video || adPlaying() || Date.now() < applyingUntil) return
    if (event.type === 'seeking') {
      if (Date.now() < gestureUntil) seekingUntil = Date.now() + 10_000
      return
    }
    const user = Date.now() < gestureUntil || (event.type === 'seeked' && Date.now() < seekingUntil)
    if (!user && event.type !== 'ended') return
    if (event.type === 'seeked') seekingUntil = 0
    send({ type: 'intent', action: event.type === 'seeked' ? 'seek' : event.type === 'ended' ? 'pause' : event.type === 'ratechange' ? 'rate' : event.type, position: video.currentTime, rate: video.playbackRate, videoId: videoId() })
  }
  function bindVideo() {
    const next = document.querySelector('#movie_player video.html5-main-video')
    if (video === next) return
    for (const event of ['play', 'pause', 'seeking', 'seeked', 'ratechange', 'ended']) {
      video?.removeEventListener(event, localEvent)
      next?.addEventListener(event, localEvent)
    }
    video = next
    applyingUntil = Date.now() + 1500
  }
  function snapshot() {
    if (!host.isConnected) document.documentElement.append(host)
    bindVideo()
    const id = videoId()
    let buffered = 0
    if (video) for (let index = 0; index < video.buffered.length; index++) {
      if (video.currentTime >= video.buffered.start(index) && video.currentTime <= video.buffered.end(index)) buffered = video.buffered.end(index) - video.currentTime
    }
    send({ type: 'state', videoId: id, title: document.querySelector('h1.ytd-watch-metadata')?.textContent?.trim() || document.title.replace(/ - YouTube$/, ''), position: video?.currentTime || 0, duration: Number.isFinite(video?.duration) ? video.duration : 0, paused: video?.paused ?? true, rate: video?.playbackRate || 1, volume: video?.volume ?? 1, ready: !!video && video.readyState >= 3, seeking: video?.seeking || Date.now() < seekingUntil, ad: adPlaying(), buffered, available: !!video && /^[A-Za-z0-9_-]{11}$/.test(id || ''), live: !!video && !Number.isFinite(video.duration) })
  }
  window.addEventListener('message', async event => {
    if (event.source !== frame.contentWindow || event.origin !== extensionOrigin || event.data?.source !== 'watchparty-extension') return
    const command = event.data
    if (command.type === 'hello') { snapshot(); return }
    if (command.type === 'layout') {
      if (Number.isFinite(command.opacity)) panel.style.opacity = String(Math.max(.5, Math.min(1, command.opacity)))
      if (['left', 'right'].includes(command.dock)) {
        host.style.left = command.dock === 'left' ? '18px' : 'auto'
        host.style.right = command.dock === 'right' ? '18px' : 'auto'
        host.style.top = 'auto'; host.style.bottom = '18px'
      }
      return
    }
    if (command.type === 'navigate' && /^[A-Za-z0-9_-]{11}$/.test(command.videoId)) {
      location.assign(`https://www.youtube.com/watch?v=${encodeURIComponent(command.videoId)}`)
      return
    }
    if (!video || adPlaying() || command.videoId !== videoId()) return
    if (command.type === 'volume' && Number.isFinite(command.volume)) { video.volume = Math.max(0, Math.min(1, command.volume)); return }
    if (command.type !== 'apply' || typeof command.paused !== 'boolean') return
    applyingUntil = Date.now() + 1200
    if (Number.isFinite(command.position) && command.position >= 0 && Math.abs(video.currentTime - command.position) > .05) video.currentTime = Math.min(command.position, Number.isFinite(video.duration) ? Math.max(0, video.duration - .05) : command.position)
    if (Number.isFinite(command.rate) && command.rate >= .25 && command.rate <= 2.2 && Math.abs(video.playbackRate - command.rate) > .005) video.playbackRate = command.rate
    if (command.paused && !video.paused) video.pause()
    if (!command.paused && video.paused) {
      try { await video.play() }
      catch { send({ type: 'error', message: 'YouTube blocked autoplay. Click Play on the YouTube player once to enable playback.' }) }
    }
  })
  setInterval(snapshot, 500)
})()
