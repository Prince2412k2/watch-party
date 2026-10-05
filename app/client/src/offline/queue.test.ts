import test from 'node:test'
import assert from 'node:assert/strict'
import { runChunkQueue } from './queue.ts'

test('three chunks overlap, with bounded work and each index processed once', async () => {
  const started: number[] = [],
    gates: (() => void)[] = []
  const task = runChunkQueue(
    7,
    async (index) => {
      started.push(index)
      await new Promise<void>((resolve) => (gates[index] = resolve))
    },
    new AbortController().signal
  )
  assert.deepEqual(started, [0, 1, 2])
  gates[1]()
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.deepEqual(started, [0, 1, 2, 3])
  gates[0]()
  gates[2]()
  gates[3]()
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.deepEqual(started, [0, 1, 2, 3, 4, 5, 6])
  gates[4]()
  gates[5]()
  gates[6]()
  await task
})
test('pause drains in-flight chunks without scheduling later chunks', async () => {
  const controller = new AbortController(),
    started: number[] = [],
    gates: (() => void)[] = []
  const task = runChunkQueue(
    12,
    async (index) => {
      started.push(index)
      await new Promise<void>((resolve) => (gates[index] = resolve))
    },
    controller.signal
  )
  const rejected = assert.rejects(task, { name: 'AbortError' })
  controller.abort()
  gates.forEach((release) => release())
  await rejected
  assert.deepEqual(started, [0, 1, 2])
})
test('a failed chunk stops the queue and drains sibling writes before rejecting', async () => {
  const started: number[] = [],
    gates: (() => void)[] = [],
    finished: number[] = []
  const task = runChunkQueue(
    9,
    async (index) => {
      started.push(index)
      await new Promise<void>((resolve) => (gates[index] = resolve))
      if (index === 1) throw new Error('Storage full')
      finished.push(index)
    },
    new AbortController().signal
  )
  const rejected = assert.rejects(task, /Storage full/)
  gates[1]()
  await new Promise((resolve) => setTimeout(resolve, 0))
  gates[0]()
  gates[2]()
  await rejected
  assert.deepEqual(started, [0, 1, 2])
  assert.deepEqual(finished.sort(), [0, 2])
})
