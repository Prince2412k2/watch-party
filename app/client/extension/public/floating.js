// Flutter FloatingTileGeometry parity: 4:3, min 112, default 168, avatar 60,
// margin 16 and edge snap 18. The viewport is the only maximum tile size.
globalThis.WatchPartyCameraLayer = class {
  constructor(shadow, frameUrl, report) {
    this.root = document.createElement('div'); this.root.className = 'camera-layer'
    this.tiles = new Map(); this.frameUrl = frameUrl; this.report = report; this.z = 1
    shadow.append(this.root)
    window.addEventListener('resize', () => { for (const tile of this.tiles.values()) this.place(tile) })
  }
  place(tile, snap = false) {
    tile.width = Math.max(112, Math.min(tile.width, Math.max(112, innerWidth - 32), Math.max(112, (innerHeight - 32) * 4 / 3)))
    const w = tile.collapsed ? 60 : tile.width, h = tile.collapsed ? 60 : tile.width * .75
    const maxX = Math.max(0, innerWidth - w), maxY = Math.max(0, innerHeight - h)
    tile.x = Math.max(0, Math.min(maxX, tile.x)); tile.y = Math.max(0, Math.min(maxY, tile.y))
    if (snap) {
      if (tile.x < 34) tile.x = Math.min(16, maxX)
      if (tile.y < 34) tile.y = Math.min(16, maxY)
      if (tile.x > maxX - 34) tile.x = Math.max(0, maxX - 16)
      if (tile.y > maxY - 34) tile.y = Math.max(0, maxY - 16)
    }
    Object.assign(tile.node.style, { left: `${tile.x}px`, top: `${tile.y}px`, width: `${w}px`, height: `${h}px` })
    tile.node.className = `floating-camera${tile.collapsed ? ' collapsed' : ''}${tile.speaking ? ' speaking' : ''}`
    tile.frame.hidden = tile.collapsed; tile.ball.hidden = !tile.collapsed
  }
  save(tile) { this.report({ type: 'camera-layout', owner: this.owner, id: tile.id, layout: { x: tile.x, y: tile.y, width: tile.width, collapsed: tile.collapsed, customized: tile.customized } }) }
  update({ owner, people, layouts = {}, defaultWidth = 168 }) {
    this.owner = owner
    const capacity = Math.max(1, Math.floor((innerWidth - 448) / (defaultWidth + 8))) * Math.max(1, Math.floor((innerHeight - 32) / (defaultWidth * .75 + 8)))
    this.root.className = people.length > capacity ? 'camera-layer overflow-rail' : 'camera-layer'
    const live = new Set(people.map(person => person.id))
    for (const [id, tile] of this.tiles) if (!live.has(id) || tile.owner !== owner) { tile.node.remove(); this.tiles.delete(id) }
    people.forEach((person, index) => {
      let tile = this.tiles.get(person.id)
      if (!tile) {
        const width = Math.max(112, Number(defaultWidth) || 168), height = width * .75
        const rows = Math.max(1, Math.floor((innerHeight - 24) / (height + 8)))
        tile = { id: person.id, owner, width, x: innerWidth - width - 448 - Math.floor(index / rows) * (width + 8), y: innerHeight - 16 - (index % rows + 1) * (height + 8), collapsed: false, customized: false, ...layouts[person.id] }
        const node = document.createElement('section'); node.setAttribute('aria-label', `${person.name} floating camera`)
        const frame = document.createElement('iframe'); frame.src = `${this.frameUrl}?owner=${encodeURIComponent(owner)}&id=${encodeURIComponent(person.id)}`; frame.title = `${person.name} camera`; frame.allow = 'autoplay'
        const bar = document.createElement('div'); bar.className = 'camera-drag'
        const label = document.createElement('span'); label.textContent = person.name
        const collapse = document.createElement('button'); collapse.textContent = '−'; collapse.title = `Collapse ${person.name}`
        const ball = document.createElement('button'); ball.className = 'camera-ball'; ball.textContent = person.name.slice(0, 1).toUpperCase(); ball.title = `Expand ${person.name}`
        const resize = document.createElement('div'); resize.className = 'camera-resize'; resize.setAttribute('role', 'slider'); resize.setAttribute('aria-label', `Resize ${person.name} camera`); resize.tabIndex = 0
        Object.assign(tile, { node, frame, ball, label })
        const toggle = () => { tile.collapsed = !tile.collapsed; tile.customized = true; this.place(tile, true); this.save(tile) }
        let moved = false
        collapse.onclick = () => { moved = false; toggle() }; ball.onclick = () => { if (moved) { moved = false; return }; toggle() }
        let operation = null
        for (const [element, kind] of [[bar, 'drag'], [resize, 'resize'], [ball, 'drag']]) {
          element.addEventListener('pointerdown', event => {
            if (event.target.closest('button') && event.target !== ball) return
            tile.node.style.zIndex = String(++this.z)
            moved = false; event.preventDefault(); operation = { kind, x: event.clientX, y: event.clientY, left: tile.x, top: tile.y, width: tile.width }; element.setPointerCapture(event.pointerId)
          })
          element.addEventListener('pointermove', event => {
            if (!operation) return
            if (Math.abs(event.clientX - operation.x) + Math.abs(event.clientY - operation.y) > 4) moved = true
            tile.customized = true
            if (operation.kind === 'resize') tile.width = operation.width + event.clientX - operation.x
            else { tile.x = operation.left + event.clientX - operation.x; tile.y = operation.top + event.clientY - operation.y }
            this.place(tile)
          })
          for (const type of ['pointerup', 'pointercancel']) element.addEventListener(type, () => { if (!operation) return; operation = null; this.place(tile, true); this.save(tile) })
        }
        resize.addEventListener('keydown', event => {
          if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) return
          event.preventDefault(); tile.width += ['ArrowRight', 'ArrowUp'].includes(event.key) ? 16 : -16; tile.customized = true; this.place(tile); this.save(tile)
        })
        bar.append(label, collapse); node.append(frame, bar, resize, ball); this.root.append(node); this.tiles.set(person.id, tile)
      }
      tile.label.textContent = person.name; tile.speaking = person.speaking
      if (!tile.customized) tile.width = defaultWidth
      this.place(tile)
    })
  }
}
