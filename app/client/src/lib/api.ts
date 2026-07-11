// Tiny fetch helpers shared across the download pages. Previously duplicated
// (with drifted signatures) in Downloads.jsx / FindDownload.jsx / DownloadDetail.jsx.
// All requests send the session cookie; `signal` is optional for cancellation.
export const jget = (url, signal = undefined) => fetch(url, { credentials: 'include', signal })

export const jpost = (url, body) => fetch(url, {
  method: 'POST', credentials: 'include',
  headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
})

export const jdelete = (url) => fetch(url, { method: 'DELETE', credentials: 'include' })
