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
  style.textContent += `.launcher{display:flex;align-items:center;gap:9px;padding:11px 14px;background:#241d1f;border-color:#62474b;border-radius:10px;font-weight:500;box-shadow:0 4px 24px #1a0b0d66}.launcher::before{content:'';width:21px;height:21px;background:url('${chrome.runtime.getURL('brand.svg')}') center/contain no-repeat}.panel{width:392px;height:min(760px,calc(100vh - 40px));background:#171616;border-color:#4d3a3e;border-radius:15px;box-shadow:0 12px 45px #150a0c88}.bar{height:34px;min-height:34px;padding:5px 8px;background:#201b1d;border-bottom:1px solid #392c30}.bar strong{display:flex;align-items:center;gap:7px;color:#b8a7a0;font-size:10px;font-weight:400}.bar strong::before{content:'';width:7px;height:10px;opacity:.6;background:radial-gradient(circle,#b8a7a0 1px,transparent 1.5px) 0 0/4px 4px}.bar button{background:#2b2225;border-color:#503b42;border-radius:5px;color:#ddc8cb;font-size:9px;min-height:23px;padding:4px 7px}.bar button:hover{background:#3a292f}`
  launcher.className = 'launcher'
  style.textContent += '.panel{width:420px;height:min(840px,calc(100vh - 40px))}.bar{height:38px;min-height:38px}.bar strong{font-size:11px}.bar button{font-size:11px;min-height:27px}'
  launcher.textContent = 'Watch Party'
  const panel = document.createElement('section')
  panel.className = 'panel'
  panel.setAttribute('aria-label', 'Watch Party overlay')
  panel.hidden = true
  const bar = document.createElement('div')
  bar.className = 'bar'
  const title = document.createElement('strong')
  title.textContent = 'Move panel'
  const fullscreen = document.createElement('button')
  fullscreen.textContent = 'Fullscreen'
  const hide = document.createElement('button')
  hide.textContent = 'Hide'
  hide.title = 'Hide overlay; your room stays connected'
  const frame = document.createElement('iframe')
  frame.src = chrome.runtime.getURL('index.html')
  frame.allow = 'camera; microphone; speaker-selection; clipboard-write; autoplay; fullscreen'
  frame.title = 'Watch Party room, chat, and cameras'
  frame.referrerPolicy = 'no-referrer'
  // Keep the owner iframe in the document's light tree so sibling extension
  // camera frames can discover its WindowProxy without involving YouTube in
  // camera transport. A slot still isolates the surrounding panel styles.
  frame.slot = 'room'
  frame.style.cssText = 'display:block;width:100%;height:100%;min-height:0;border:0;background:#171d22;'
  const roomSlot = document.createElement('slot')
  roomSlot.name = 'room'
  roomSlot.style.cssText = 'display:block;flex:1;min-height:0;'
  bar.append(title, fullscreen, hide)
  panel.append(bar, roomSlot)
  shadow.append(style, launcher, panel)
  host.append(frame)
  document.documentElement.append(host)

  const camerasHost = document.createElement('div')
  camerasHost.id = 'watchparty-cameras-root'
  camerasHost.style.cssText = 'position:fixed;inset:0;z-index:2147483646;pointer-events:none;'
  const camerasShadow = camerasHost.attachShadow({ mode: 'closed' })
  const cameraStyle = document.createElement('style')
  cameraStyle.textContent = `:host{pointer-events:none;font:11px system-ui,sans-serif;color:#eef2f3}.camera-layer{position:absolute;inset:0;pointer-events:none}.floating-camera{position:absolute;pointer-events:auto;overflow:hidden;border:1px solid #46535b;border-radius:9px;background:#11171b;box-shadow:0 4px 20px #0006}.floating-camera.speaking{border-color:#98d3b9;box-shadow:0 0 0 1px #98d3b9}.floating-camera iframe{display:block;width:100%;height:100%;border:0}.camera-drag{position:absolute;top:0;left:0;right:0;height:26px;display:flex;align-items:center;gap:4px;padding:0 5px 0 7px;background:#171d22bd;cursor:move;touch-action:none;opacity:0}.floating-camera:hover .camera-drag,.floating-camera:focus-within .camera-drag{opacity:1}.camera-drag span{flex:1;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}.camera-drag button{border:0;background:transparent;color:#eef2f3;cursor:pointer;font:18px system-ui;min-width:24px}.camera-resize{position:absolute;right:0;bottom:0;width:18px;height:18px;cursor:nwse-resize;touch-action:none;background:linear-gradient(135deg,transparent 60%,#98d3b9 61%,#98d3b9 68%,transparent 69%)}.collapsed{border-radius:50%}.collapsed .camera-drag,.collapsed .camera-resize{display:none}.camera-ball{width:100%;height:100%;border:0;background:#34463d;color:#bfdecf;font:26px system-ui;cursor:pointer}.camera-ball:focus-visible{outline:2px solid #98d3b9;outline-offset:-3px}[hidden]{display:none!important}`
  camerasShadow.append(cameraStyle)
  cameraStyle.textContent += '.floating-camera{border-color:#5e4148;border-radius:10px;box-shadow:0 5px 22px #170b0d77}.floating-camera.speaking{border-color:#a7cfb0;box-shadow:0 0 0 1px #a7cfb0}.camera-drag{background:#20151adb;color:#ecdad4}.camera-drag span{font-size:10px}.camera-drag button{color:#edbdc2}.camera-ball{background:#3b292f;color:#edbdc2}.camera-ball:focus-visible{outline-color:#ef767b}.camera-resize{background:linear-gradient(135deg,transparent 60%,#ef767b 61%,#ef767b 68%,transparent 69%)}'
  cameraStyle.textContent += '.camera-layer.overflow-rail{inset:64px 448px 112px auto;display:flex;flex-direction:column;gap:8px;width:184px;overflow-y:auto;pointer-events:auto;padding:4px}.overflow-rail .floating-camera{position:relative!important;left:0!important;top:0!important;width:168px!important;height:126px!important;flex:none}.overflow-rail .floating-camera.collapsed{width:60px!important;height:60px!important}'
  document.documentElement.append(camerasHost)
  const cameras = new globalThis.WatchPartyCameraLayer(camerasShadow, chrome.runtime.getURL('camera.html'), data => send(data))

  launcher.onclick = () => { panel.hidden = false; launcher.hidden = true; snapshot() }
  hide.onclick = () => { panel.hidden = true; launcher.hidden = false }
  async function toggleFullscreen() {
    try {
      if (document.fullscreenElement) await document.exitFullscreen()
      else await (document.querySelector('ytd-reel-video-renderer[is-active]') || document.querySelector('#movie_player') || document.documentElement).requestFullscreen()
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
    if (target.moveBefore && camerasHost.isConnected) target.moveBefore(camerasHost, null)
    else target.append(camerasHost)
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
  const videoId = () => {
    const url = new URL(location.href)
    return url.pathname === '/watch' ? url.searchParams.get('v') : /^\/shorts\/([A-Za-z0-9_-]{11})/.exec(url.pathname)?.[1] ?? null
  }
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
    const next = location.href.includes('/shorts/') ? document.querySelector('ytd-reel-video-renderer[is-active] video') : document.querySelector('#movie_player video.html5-main-video')
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
    if (!camerasHost.isConnected) document.documentElement.append(camerasHost)
    bindVideo()
    const id = videoId()
    let buffered = 0
    if (video) for (let index = 0; index < video.buffered.length; index++) {
      if (video.currentTime >= video.buffered.start(index) && video.currentTime <= video.buffered.end(index)) buffered = video.buffered.end(index) - video.currentTime
    }
    const page = new URL(location.href); page.hash = ''
    send({ type: 'state', url: page.href, videoId: id, title: document.querySelector('h1.ytd-watch-metadata')?.textContent?.trim() || document.title.replace(/ - YouTube$/, ''), position: video?.currentTime || 0, duration: Number.isFinite(video?.duration) ? video.duration : 0, paused: video?.paused ?? true, rate: video?.playbackRate || 1, volume: video?.volume ?? 1, ready: !!video && video.readyState >= 3, seeking: video?.seeking || Date.now() < seekingUntil, ad: adPlaying(), buffered, available: !!video && /^[A-Za-z0-9_-]{11}$/.test(id || ''), live: !!video && !Number.isFinite(video.duration) })
  }
  window.addEventListener('message', async event => {
    if (!event.isTrusted || event.source !== frame.contentWindow || event.origin !== extensionOrigin || event.data?.source !== 'watchparty-extension') return
    const command = event.data
    if (command.type === 'hello') { snapshot(); return }
    if (command.type === 'open') { panel.hidden = false; launcher.hidden = true; return }
    if (command.type === 'cameras' && typeof command.owner === 'string' && Array.isArray(command.people)) { cameras.update(command); return }
    if (command.type === 'layout') {
      if (Number.isFinite(command.opacity)) panel.style.opacity = String(Math.max(.5, Math.min(1, command.opacity)))
      if (['left', 'right'].includes(command.dock)) {
        host.style.left = command.dock === 'left' ? '18px' : 'auto'
        host.style.right = command.dock === 'right' ? '18px' : 'auto'
        host.style.top = 'auto'; host.style.bottom = '18px'
      }
      return
    }
    if (command.type === 'navigate' && typeof command.url === 'string') {
      let target
      try { target = new URL(command.url) } catch { return }
      if (target.origin !== 'https://www.youtube.com' || target.username || target.password) return
      if (target.href !== location.href) location.assign(target.href)
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
