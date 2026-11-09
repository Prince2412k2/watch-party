import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'

const source = readFileSync(new URL('../public/content.js', import.meta.url), 'utf8')

function harness() {
  const sent = [], windows = {}, documents = {}, intervals = [], nodes = []
  let now = 10_000, ad = false
  class Element {
    constructor(tag) { this.tagName = tag.toUpperCase(); this.style = {}; this.children = []; this.listeners = {}; this.hidden = false; this.isConnected = true; nodes.push(this) }
    append(...nodes) { this.children.push(...nodes) }
    moveBefore(node) { this.atomicMoves = (this.atomicMoves ?? 0) + 1; this.children.push(node) }
    attachShadow() { return new Element('shadow') }
    setAttribute() {}
    addEventListener(event, fn) { (this.listeners[event] ??= new Set()).add(fn) }
    removeEventListener(event, fn) { this.listeners[event]?.delete(fn) }
    fire(type, extra = {}) { for (const fn of this.listeners[type] ?? []) fn({ type, target: this, ...extra }) }
    closest(selector) { return selector === 'button' && this.tagName === 'BUTTON' ? this : null }
    contains(target) { return target === video }
    async requestFullscreen() { document.fullscreenElement = this; documents.fullscreenchange() }
  }
  const video = new Element('video')
  Object.assign(video, { currentTime: 5, duration: 300, paused: true, playbackRate: 1, volume: .8, readyState: 4, seeking: false, buffered: { length: 1, start: () => 0, end: () => 40 } })
  video.pause = () => { video.paused = true; video.fire('pause') }
  video.play = async () => { video.paused = false; video.fire('play') }
  const player = new Element('player'), root = new Element('html')
  const document = {
    documentElement: root, title: 'Example - YouTube', fullscreenElement: null,
    getElementById: () => null,
    createElement(tag) { const node = new Element(tag); if (tag === 'iframe') node.contentWindow = { postMessage: data => sent.push(data) }; return node },
    addEventListener: (name, fn) => { documents[name] = fn },
    querySelector(selector) {
      if (selector.includes('.ad-showing')) return ad ? player : null
      if (selector.includes('video.html5-main-video')) return video
      if (selector === '#movie_player') return player
      return null
    },
    async exitFullscreen() { document.fullscreenElement = null; documents.fullscreenchange() },
  }
  const window = { addEventListener: (name, fn) => { windows[name] = fn } }
  runInNewContext(source, { document, window, chrome: { runtime: { getURL: path => `chrome-extension://test-id/${path.replace(/^\//, '')}` } }, location: { href: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', assign() {} }, URL, Date: class extends Date { static now() { return now } }, innerWidth: 1400, innerHeight: 900, setInterval: fn => intervals.push(fn) })
  const host = root.children[0]
  const frame = nodes.find(node => node.tagName === 'IFRAME')
  intervals[0]()
  const apply = (data, origin = 'chrome-extension://test-id', source = frame.contentWindow) => windows.message({ source, origin, data: { source: 'watchparty-extension', type: 'apply', videoId: 'dQw4w9WgXcQ', ...data } })
  return { sent, video, player, document, documents, windows, apply, tick: () => intervals[0](), advance: ms => { now += ms }, setAd: value => { ad = value }, host }
}

test('content bridge reports the current video and native playback settings', () => {
  const h = harness()
  const state = h.sent.at(-1)
  assert.equal(state.videoId, 'dQw4w9WgXcQ')
  assert.equal(state.position, 5)
  assert.equal(state.volume, .8)
  assert.equal(state.available, true)
})
test('trusted YouTube gestures author playback, not arbitrary media events', () => {
  const h = harness()
  h.advance(2000)
  h.video.fire('play')
  assert.equal(h.sent.filter(event => event.type === 'intent').length, 0)
  h.documents.pointerdown({ isTrusted: true, target: h.video })
  h.video.fire('play')
  assert.equal(h.sent.at(-1).action, 'play')
  h.video.fire('seeking')
  h.advance(2500)
  h.video.currentTime = 42
  h.video.fire('seeked')
  assert.equal(h.sent.at(-1).action, 'seek')
  assert.equal(h.sent.at(-1).position, 42)
})
test('ad playback never authors room timeline changes', () => {
  const h = harness()
  h.advance(2000); h.setAd(true)
  h.documents.pointerdown({ isTrusted: true, target: h.video })
  h.video.fire('play'); h.video.fire('pause'); h.video.fire('ended')
  assert.equal(h.sent.filter(event => event.type === 'intent').length, 0)
  h.tick()
  assert.equal(h.sent.at(-1).ad, true)
})
test('YouTube keyboard shortcuts count as intent outside the player, but text inputs do not', () => {
  const h = harness()
  h.advance(2000)
  h.documents.keydown({ isTrusted: true, target: { tagName: 'INPUT' }, key: 'k' })
  h.video.fire('play')
  assert.equal(h.sent.filter(event => event.type === 'intent').length, 0)
  h.documents.keydown({ isTrusted: true, target: { tagName: 'BODY' }, key: 'k' })
  h.video.fire('play')
  assert.equal(h.sent.at(-1).action, 'play')
})
test('remote corrections do not echo as locally authored commands', async () => {
  const h = harness()
  h.advance(2000)
  h.documents.pointerdown({ isTrusted: true, target: h.video })
  await h.apply({ paused: false, position: 25, rate: 1.5 })
  assert.equal(h.video.currentTime, 25)
  assert.equal(h.video.paused, false)
  assert.equal(h.sent.filter(event => event.type === 'intent').length, 0)
})
test('foreign windows and origins cannot control the player', async () => {
  const h = harness()
  await h.apply({ paused: false, position: 25 }, 'https://www.youtube.com')
  await h.apply({ paused: false, position: 25 }, 'chrome-extension://test-id', {})
  assert.equal(h.video.currentTime, 5)
  assert.equal(h.video.paused, true)
})
test('commands for an old video or an ad cannot seek the current player', async () => {
  const h = harness()
  await h.apply({ paused: false, position: 25, videoId: 'aaaaaaaaaaa' })
  h.setAd(true)
  await h.apply({ paused: false, position: 25 })
  assert.equal(h.video.currentTime, 5)
})
test('fullscreen moves the floating overlay into the actual fullscreen subtree', async () => {
  const h = harness()
  await h.player.requestFullscreen()
  assert.equal(h.player.children.at(-1), h.host)
  assert.equal(h.player.atomicMoves, 1, 'fullscreen must use atomic movement to avoid reloading the room iframe')
  await h.document.exitFullscreen()
  assert.equal(h.document.documentElement.children.at(-1), h.host)
})
