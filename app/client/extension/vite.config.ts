import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'
import { copyFileSync, mkdirSync } from 'node:fs'

export default defineConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
  base: './',
  plugins: [react(), {
    name: 'watchparty-brand-assets',
    closeBundle() {
      const output = fileURLToPath(new URL('./dist/', import.meta.url))
      mkdirSync(`${output}/fonts`, { recursive: true })
      for (const weight of ['Light', 'Book', 'Bold']) copyFileSync(fileURLToPath(new URL(`../public/fonts/CircularXXWeb-${weight}.woff2`, import.meta.url)), `${output}/fonts/CircularXXWeb-${weight}.woff2`)
      copyFileSync(fileURLToPath(new URL('../public/icon.svg', import.meta.url)), `${output}/brand.svg`)
      copyFileSync(fileURLToPath(new URL('../public/icon-192.png', import.meta.url)), `${output}/icon-192.png`)
    },
  }],
  define: { 'process.env': {} },
  build: {
    outDir: 'dist', emptyOutDir: true, target: 'es2022',
    rollupOptions: {
      input: { room: fileURLToPath(new URL('./index.html', import.meta.url)), popup: fileURLToPath(new URL('./popup.html', import.meta.url)), background: fileURLToPath(new URL('./src/background.ts', import.meta.url)) },
      output: { entryFileNames: chunk => chunk.name === 'background' ? 'background.js' : 'assets/[name]-[hash].js' },
    },
  },
})
