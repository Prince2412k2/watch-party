import test from 'node:test'
import assert from 'node:assert/strict'
import { chatContent } from '../../../shared/chat-content.js'

test('rich chat preserves text compatibility and bounds quoted content', () => {
  assert.deepEqual(chatContent({ text: ' hello ' }), { text: 'hello' })
  assert.deepEqual(chatContent({ gif: 'https://media.giphy.com/example.gif', reply: { name: 'Guest', text: 'Earlier message' } }), { text: 'GIF', gif: 'https://media.giphy.com/example.gif', reply: { name: 'Guest', text: 'Earlier message' } })
  const result = chatContent({ text: 'a'.repeat(3000), reply: { name: 'b'.repeat(100), text: 'c'.repeat(500) } })
  assert.equal(result.text.length, 2000)
  assert.equal(result.reply.name.length, 80)
  assert.equal(result.reply.text.length, 240)
})
test('invalid, empty, and non-HTTPS rich messages are rejected', () => {
  for (const payload of [null, {}, { text: 5 }, { text: '  ' }, { gif: 'javascript:alert(1)' }, { gif: 'data:image/svg+xml,bad' }, { gif: 'http://example.org/image.gif' }, { gif: 'https://user:password@example.org/image.gif' }]) assert.equal(chatContent(payload), null)
  assert.deepEqual(chatContent({ text: 'valid', reply: { text: 4 } }), { text: 'valid' })
})
