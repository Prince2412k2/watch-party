// Barrel for the offline/download UI surface (N6). Nothing here has side
// effects at import time — everything is IS_NATIVE-gated inside the
// components/hooks themselves, so importing this module from a web bundle is
// harmless (components render null, hooks no-op).
export { default as DownloadButton } from './DownloadButton'
export { default as OfflineLibrary } from './OfflineLibrary'
export { default as DownloadProgress } from './DownloadProgress'
export { formatBytes, formatSpeed, progressPct } from './format'
