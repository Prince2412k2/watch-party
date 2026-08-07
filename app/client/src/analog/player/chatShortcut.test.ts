import test from 'node:test'
import assert from 'node:assert/strict'
import { chatShortcutContext, isEditableTarget, shouldToggleChatFromEvent } from './chatShortcut.ts'

const element = (tagName: string, isContentEditable = false) => ({ tagName, isContentEditable })

test('editable targets are recognised however they are spelled', () => {
  assert.equal(isEditableTarget(element('input')), true)
  assert.equal(isEditableTarget(element('TEXTAREA')), true)
  assert.equal(isEditableTarget(element('select')), true)
  assert.equal(isEditableTarget(element('DIV', true)), true)
  assert.equal(isEditableTarget(element('div')), false)
  assert.equal(isEditableTarget(null), false)
  assert.equal(isEditableTarget(undefined), false)
})

test('Ctrl+C opens chat when there is nothing to copy', () => {
  assert.equal(shouldToggleChatFromEvent({ key: 'c', ctrlKey: true }), true)
  assert.equal(shouldToggleChatFromEvent({ key: 'C', metaKey: true }), true)
})

test('copy always wins over the chat shortcut', () => {
  // Both halves of the guard, because both are how a naive binding gets caught:
  // a selection anywhere on the page, and focus inside a field.
  assert.equal(
    shouldToggleChatFromEvent({ key: 'c', ctrlKey: true }, { selectionText: 'some selected text' }),
    false,
  )
  assert.equal(
    shouldToggleChatFromEvent({ key: 'c', ctrlKey: true, target: element('input') }),
    false,
  )
  assert.equal(
    shouldToggleChatFromEvent({ key: 'c', ctrlKey: true }, { activeElement: element('DIV', true) }),
    false,
  )
  // Whitespace is not a selection.
  assert.equal(shouldToggleChatFromEvent({ key: 'c', ctrlKey: true }, { selectionText: '  \n ' }), true)
})

test('the shortcut claims nothing it was not given', () => {
  assert.equal(shouldToggleChatFromEvent({ key: 'c' }), false, 'plain c is a separate binding')
  assert.equal(shouldToggleChatFromEvent({ key: 'v', ctrlKey: true }), false)
  assert.equal(shouldToggleChatFromEvent({ key: 'c', ctrlKey: true, altKey: true }), false)
  // Ctrl+Shift+C is the devtools element picker in Chrome and Firefox alike.
  assert.equal(shouldToggleChatFromEvent({ key: 'C', ctrlKey: true, shiftKey: true }), false)
})

test('the DOM context handed to the shared guard', () => {
  const context = chatShortcutContext(
    { key: 'c', metaKey: true, target: element('div') },
    { activeElement: element('body'), selectionText: 'x' },
  )
  assert.deepEqual(context, { ctrlOrMeta: true, key: 'c', editable: false, hasSelection: true })
})
