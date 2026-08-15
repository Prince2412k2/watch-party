import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const API_TARGET = process.env.API_TARGET || 'http://localhost:3001'

export default defineConfig({
  plugins: [react()],
  // react-rnd / react-draggable reference process.env for debug logging,
  // which doesn't exist in the browser and throws on drag start.
  define: { 'process.env': {} },
  optimizeDeps: {
    include: [
      '@videojs/react',
      '@videojs/react/video',
      '@videojs/react/media/hls-video',
    ],
  },
  server: {
    host: true,
    allowedHosts: ['dsk-4161', 'dsk-4161.tail0a3558.ts.net'],
    // Behind Tailscale Serve, the browser reaches us over HTTPS on 443;
    // tell Vite's HMR client to use that port instead of 5173.
    hmr: { clientPort: 443 },
    proxy: {
      // Where the API lives. Defaults to a server on this machine; point it
      // somewhere else to run this frontend against another backend without
      // touching the code:
      //
      //   API_TARGET=https://your-host npm run dev
      //
      // `changeOrigin` matters for a remote target — the Host header has to say
      // the backend's name or its TLS front end will not route the request.
      '/api': { target: API_TARGET, changeOrigin: true },
      '/socket.io': {
        target: API_TARGET,
        ws: true,
        changeOrigin: true,
      },
      // Jellyfin media (manifest + segments) — keeps everything same-origin
      '/jellyfin': {
        target: process.env.JELLYFIN_URL || 'http://localhost:8096',
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/jellyfin/, ''),
      },
      // LiveKit signaling over wss (page is HTTPS → ws:// would be mixed-content).
      // Media (UDP/ICE) still goes direct to node_ip; only signaling is proxied.
      '/livekit': {
        target: 'ws://localhost:7880',
        ws: true,
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/livekit/, ''),
      },
    },
  },
})
