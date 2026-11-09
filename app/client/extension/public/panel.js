// Sibling extension frames share the owner's React tree, not a second socket.
const params = new URLSearchParams(location.search)
function announce() {
  for (let index = 0; index < parent.length; index++) {
    const candidate = parent.frames[index]
    try {
      if (candidate !== window && candidate.location.origin === location.origin && candidate.location.pathname.endsWith('/index.html')) candidate.postMessage({ source: 'watchparty-panel-ready', owner: params.get('owner'), id: params.get('id') }, location.origin)
    } catch { /* Ignore cross-origin YouTube frames. */ }
  }
}
const timer = setInterval(announce, 500)
announce()
window.addEventListener('message', event => {
  if (event.isTrusted && event.origin === location.origin && event.data?.source === 'watchparty-panel-owner' && event.data.owner === params.get('owner')) clearInterval(timer)
})
