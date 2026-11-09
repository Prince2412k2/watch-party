// Same-origin extension frames let the owner attach its LiveKit tracks through
// React portals. Camera pixels and streams never pass through the YouTube page.
const params = new URLSearchParams(location.search)
function announce() {
  for (let index = 0; index < window.parent.length; index++) {
    const candidate = window.parent.frames[index]
    try {
      if (candidate !== window && candidate.location.origin === location.origin && candidate.location.pathname.endsWith('/index.html')) candidate.postMessage({ source: 'watchparty-camera-ready', owner: params.get('owner'), id: params.get('id') }, location.origin)
    } catch { /* Ignore other cross-origin YouTube frames. */ }
  }
}
const timer = setInterval(announce, 500)
announce()
window.addEventListener('message', event => {
  if (event.isTrusted && event.origin === location.origin && event.data?.source === 'watchparty-camera-owner' && event.data.owner === params.get('owner')) clearInterval(timer)
})
