/** iOS standalone can retain a smaller fixed-position viewport after launch or
 * keyboard dismissal. Size app surfaces explicitly from the window, not the
 * stale bottom:0 containing block. Never use screen.height (it includes OS UI). */
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
        ? window.innerHeight
        : (viewport?.height ?? window.innerHeight)
    document.documentElement.style.setProperty(
      '--app-vh',
      `${Math.round(height)}px`
    )
  }
  update()
  window.addEventListener('resize', update)
  window.addEventListener('pageshow', update)
  document.addEventListener('focusin', update)
  document.addEventListener('focusout', update)
  window.visualViewport?.addEventListener('resize', update)
  document.addEventListener('visibilitychange', update)
}
