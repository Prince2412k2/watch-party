globalThis.WatchPartyPanelLayer = class {
  constructor(shadow, host, frameUrl, report) {
    this.shadow = shadow; this.host = host; this.frameUrl = frameUrl; this.report = report; this.panels = new Map()
    window.addEventListener('resize', () => this.reflow())
  }
  reflow() { for (const panel of this.panels.values()) this.clamp(panel) }
  clamp(panel) {
    if (panel.id === 'chat') panel.node.style.height = `${Math.max(0, innerHeight - 24)}px`
    const rect = panel.node.getBoundingClientRect()
    // display:none has no layout box. Keep closed panels in bounds using their
    // configured size; otherwise Edge/Chromium positions chat beyond the edge.
    const width = rect.width || Math.min(parseFloat(panel.node.style.width) || 312, Math.max(0, innerWidth - 32))
    const height = rect.height || parseFloat(panel.node.style.height) || 0
    if (!panel.customized) {
      panel.x = panel.id === 'chat' ? innerWidth - width - 20 : 20
      if (panel.id === 'av') panel.x = (innerWidth - width) / 2
      panel.y = panel.id === 'av' ? innerHeight - height - 24 : 20
    }
    panel.x = Math.max(12, Math.min(Math.max(12, innerWidth - width - 12), panel.x))
    panel.y = panel.id === 'chat' ? 12 : Math.max(0, Math.min(Math.max(0, innerHeight - Math.min(height, innerHeight)), panel.y))
    panel.node.style.left = `${panel.x}px`; panel.node.style.top = `${panel.y}px`
  }
  visible(panel, visible) {
    panel.node.hidden = !visible
    if (visible) this.clamp(panel)
    if (panel.reopen) panel.reopen.hidden = visible
    if (panel.id === 'chat' && visible) this.notify(0)
    this.report({ type: 'panel-visibility', owner: this.owner, id: panel.id, visible })
  }
  toggle(id) { const panel = this.panels.get(id); if (panel) this.visible(panel, panel.node.hidden) }
  notify(count) {
    const panel = this.panels.get('chat')
    if (!panel?.reopen) return
    const unread = panel.node.hidden ? Math.max(0, Math.min(999, Math.floor(Number(count) || 0))) : 0
    panel.reopen.setAttribute('data-unread', String(unread > 0))
    panel.reopen.setAttribute('aria-label', unread ? `${unread} unread message${unread === 1 ? '' : 's'}. Open chat` : 'Open chat')
    panel.reopen.title = unread ? `${unread} unread message${unread === 1 ? '' : 's'}` : 'Open chat'
    panel.icon.src = this.frameUrl.replace('panel.html', unread ? 'chat-unread.svg' : 'chat.svg')
    panel.badge.hidden = !unread; panel.badge.textContent = unread > 9 ? '9+' : String(unread)
  }
  update({ owner, active }) {
    if (!active || this.owner !== owner) {
      for (const panel of this.panels.values()) { panel.node.remove(); panel.frame.remove(); panel.reopen?.remove() }
      this.panels.clear()
    }
    this.owner = owner
    if (!active || this.panels.size) return
    for (const [id, title, width, height] of [['chat', 'Chat', 312, Math.max(0, innerHeight - 24)], ['av', 'Camera & mic', 196, 52], ['status', 'Party status', 100, 32]]) {
      const node = document.createElement('section'); node.className = `panel independent-panel ${id}-window`; node.setAttribute('aria-label', title)
      Object.assign(node.style, { width: `${width}px`, height: `${height}px` })
      const bar = document.createElement('div'); bar.className = 'bar'
      const label = document.createElement('strong'); label.textContent = title
      const hide = document.createElement('button'); hide.textContent = '×'; hide.title = `Hide ${title}`; hide.setAttribute('aria-label', hide.title)
      const frame = document.createElement('iframe'); frame.src = `${this.frameUrl}?owner=${encodeURIComponent(owner)}&id=${id}`; frame.title = title; frame.allow = 'clipboard-write; autoplay'
      frame.slot = `panel-${id}`; frame.style.cssText = 'display:block;width:100%;height:100%;border:0;pointer-events:auto;'
      const slot = document.createElement('slot'); slot.name = frame.slot; slot.style.cssText = 'display:block;flex:1;min-height:0;'
      const panel = { id, node, frame, x: id === 'chat' ? Math.max(12, innerWidth - width - 20) : 20, y: id === 'av' ? Math.max(64, (innerHeight - height) / 2) : 20 }
      if (id === 'chat') {
        const reopen = document.createElement('button'); reopen.className = 'chat-reopen'; reopen.setAttribute('aria-label', 'Open chat'); reopen.title = 'Open chat'
        const icon = document.createElement('img'); icon.src = this.frameUrl.replace('panel.html', 'chat.svg'); icon.alt = ''; icon.width = 21; icon.height = 21
        const badge = document.createElement('span'); badge.className = 'chat-count'; badge.hidden = true
        reopen.append(icon, badge); panel.icon = icon; panel.badge = badge
        reopen.onclick = () => this.visible(panel, true); this.shadow.append(reopen); panel.reopen = reopen
      }
      hide.onclick = () => this.visible(panel, false)
      let drag = null
      bar.addEventListener('pointerdown', event => {
        if (event.target.closest('button')) return
        panel.customized = true
        drag = { x: event.clientX - panel.x, y: event.clientY - panel.y }; bar.setPointerCapture(event.pointerId)
      })
      bar.addEventListener('pointermove', event => { if (drag) { panel.x = event.clientX - drag.x; panel.y = event.clientY - drag.y; this.clamp(panel) } })
      for (const name of ['pointerup', 'pointercancel']) bar.addEventListener(name, () => { drag = null })
      bar.append(label, hide); if (id === 'chat') node.append(bar); node.append(slot); this.shadow.append(node); this.host.append(frame); this.panels.set(id, panel)
      this.clamp(panel); this.visible(panel, id !== 'chat')
    }
  }
}
