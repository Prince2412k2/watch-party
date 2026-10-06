/** iOS standalone can report a shorter innerHeight/visual viewport than CSS vh.
 * Keep standalone surfaces on 100vh; only measure pixels for browser chrome or
 * the keyboard. Never use screen.height (it includes OS UI). */
export function installViewport() {
  const update = () => {
    const standalone =
      matchMedia('(display-mode: standalone)').matches ||
      (navigator as Navigator & { standalone?: boolean }).standalone === true
    const viewport = window.visualViewport
    const editing = document.activeElement?.matches(
      'input, textarea, [contenteditable="true"]'
    )
    const keyboard =
      editing && viewport && viewport.height < window.innerHeight - 120
    const height =
      standalone && !keyboard
        ? '100vh'
        : `${Math.round(viewport?.height ?? window.innerHeight)}px`
    document.documentElement.style.setProperty('--app-vh', height)
  }
  update()
  window.addEventListener('resize', update)
  window.addEventListener('pageshow', update)
  document.addEventListener('focusin', update)
  document.addEventListener('focusout', update)
  window.visualViewport?.addEventListener('resize', update)
  document.addEventListener('visibilitychange', update)
}
