export function createTransportIntent() {
  let armed = null
  return {
    arm(kind = '*') { armed = kind },
    clear() { armed = null },
    consume(kind) {
      if (armed !== '*' && armed !== kind) return false
      armed = null
      return true
    },
  }
}
