// Barrel for the offline/download UI surface (N6). Nothing here has side
// effects at import time — everything is IS_NATIVE-gated inside the
// components/hooks themselves, so importing this module from a web bundle is
// harmless (components render null, hooks no-op).
export { default as DownloadButton } from './DownloadButton.jsx'
export { default as OfflineLibrary } from './OfflineLibrary.jsx'
export { default as DownloadProgress } from './DownloadProgress.jsx'
export { formatBytes, formatSpeed, progressPct } from './format.js'
