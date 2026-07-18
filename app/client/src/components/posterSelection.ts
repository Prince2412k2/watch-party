export function movePosterSelection(index: number, count: number, direction: number) {
  if (count <= 0) return 0
  return Math.max(0, Math.min(count - 1, index + Math.sign(direction)))
}
