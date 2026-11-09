globalThis.WatchPartyPanelLayer = class {
  constructor(shadow, host, frameUrl, report) {
    this.shadow = shadow; this.host = host; this.frameUrl = frameUrl; this.report = report; this.panels = new Map()
    window.addEventListener('resize', () => { for (const panel of this.panels.values()) this.clamp(panel) })
  }
  clamp(panel) {
    const rect = panel.node.getBoundingClientRect()
    panel.x = Math.max(0, Math.min(Math.max(0, innerWidth - rect.width), panel.x))
    panel.y = Math.max(0, Math.min(Math.max(0, innerHeight - Math.min(rect.height, innerHeight)), panel.y))
    panel.node.style.left = `${panel.x}px`; panel.node.style.top = `${panel.y}px`
  }
  visible(panel, visible) {
    panel.node.hidden = !visible
    this.report({ type: 'panel-visibility', owner: this.owner, id: panel.id, visible })
  }
  toggle(id) { const panel = this.panels.get(id); if (panel) this.visible(panel, panel.node.hidden) }
  update({ owner, active }) {
    if (!active || this.owner !== owner) {
      for (const panel of this.panels.values()) { panel.node.remove(); panel.frame.remove() }
      this.panels.clear()
    }
    this.owner = owner
    if (!active || this.panels.size) return
    for (const [id, title, width, height] of [['chat', 'Chat', 320, 370], ['av', 'Camera & mic', 280, 180]]) {
      const node = document.createElement('section'); node.className = `panel independent-panel ${id}-window`; node.setAttribute('aria-label', title)
      Object.assign(node.style, { width: `${width}px`, height: `${height}px` })
      const bar = document.createElement('div'); bar.className = 'bar'
      const label = document.createElement('strong'); label.textContent = title
      const hide = document.createElement('button'); hide.textContent = '−'; hide.title = `Hide ${title}`; hide.setAttribute('aria-label', hide.title)
      const frame = document.createElement('iframe'); frame.src = `${this.frameUrl}?owner=${encodeURIComponent(owner)}&id=${id}`; frame.title = title; frame.allow = 'clipboard-write; autoplay'
      frame.slot = `panel-${id}`; frame.style.cssText = 'display:block;width:100%;height:100%;border:0;pointer-events:auto;'
      const slot = document.createElement('slot'); slot.name = frame.slot; slot.style.cssText = 'display:block;flex:1;min-height:0;'
      const panel = { id, node, frame, x: 16, y: id === 'chat' ? 16 : Math.max(16, innerHeight - height - 16) }
      hide.onclick = () => this.visible(panel, false)
      let drag = null
      bar.addEventListener('pointerdown', event => {
        if (event.target.closest('button')) return
        drag = { x: event.clientX - panel.x, y: event.clientY - panel.y }; bar.setPointerCapture(event.pointerId)
      })
      bar.addEventListener('pointermove', event => { if (drag) { panel.x = event.clientX - drag.x; panel.y = event.clientY - drag.y; this.clamp(panel) } })
      for (const name of ['pointerup', 'pointercancel']) bar.addEventListener(name, () => { drag = null })
      bar.append(label, hide); node.append(bar, slot); this.shadow.append(node); this.host.append(frame); this.panels.set(id, panel)
      this.clamp(panel); this.visible(panel, true)
    }
  }
}
