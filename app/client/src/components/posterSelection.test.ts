import test from 'node:test'
import assert from 'node:assert/strict'
import { movePosterSelection } from './posterSelection.ts'

test('moves poster selection one item in either direction', () => {
  assert.equal(movePosterSelection(2, 5, 1), 3)
  assert.equal(movePosterSelection(2, 5, -1), 1)
})

test('clamps poster selection at shelf boundaries', () => {
  assert.equal(movePosterSelection(0, 5, -1), 0)
  assert.equal(movePosterSelection(4, 5, 1), 4)
  assert.equal(movePosterSelection(3, 0, 1), 0)
})
