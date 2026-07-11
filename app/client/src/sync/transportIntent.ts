export function createTransportIntent() {
  let armed: string | '*' | null = null
  return {
    arm(kind: string | '*' = '*') { armed = kind },
    clear() { armed = null },
    consume(kind: string) {
      if (armed !== '*' && armed !== kind) return false
      armed = null
      return true
    },
  }
}
