import test from 'node:test'
import assert from 'node:assert/strict'
import { assets, derivedColors, derivedConfig, effectiveConfig } from './avatar'

const IDS = [
  '8f4b2c1d', 'root', 'a7e91b33', 'prince', 'yash',
  '0000-1111', 'ffffffff', 'guest-01', 'guest-02', 'guest-03',
]

test('the same account derives a byte-identical avatar every time', () => {
  for (const id of IDS) {
    assert.equal(JSON.stringify(derivedConfig(id)), JSON.stringify(derivedConfig(id)))
  }
})

test('derived colours are pinned — changing them restyles every existing user', () => {
  // Golden values, not a re-derivation: the palettes and the seed hash are a
  // contract with everyone who has never opened the profile page, and the
  // server draws the same faces for the Flutter clients from the same module.
  // If this fails, someone reordered a palette or changed the hash.
  assert.deepEqual(derivedColors('test-alice'), {
    skin: 'EFC2A2', hair: '7A7A7A', clothes: '55606E', bottom: '8A8F97',
  })
  assert.deepEqual(derivedColors('root'), {
    skin: '623C22', hair: 'B08D57', clothes: 'D3D7DC', bottom: '7A5F4B',
  })
})

test('ten accounts derive ten different avatars', () => {
  const rendered = new Set(IDS.map(id => JSON.stringify(derivedConfig(id))))
  assert.equal(rendered.size, IDS.length)
})

test('no derived avatar keeps the asset set default of pure-white skin', () => {
  // The whole reason colour is derived rather than left alone: humation-1
  // defaults every user to FFFFFF skin.
  assert.equal(assets.defaults.colors.skin, 'FFFFFF')
  for (const id of IDS) {
    assert.notEqual(derivedConfig(id).colors?.skin, 'FFFFFF')
  }
})

test('derived avatars vary in parts as well as colours', () => {
  const heads = new Set(IDS.map(id => derivedConfig(id).selections?.head))
  const skins = new Set(IDS.map(id => derivedColors(id).skin))
  assert.ok(heads.size > 1, 'expected seeded parts to differ across accounts')
  assert.ok(skins.size > 1, 'expected derived colours to differ across accounts')
})

test('every derived avatar fills every slot the asset set defines', () => {
  const slots = assets.selectionSlots.map(slot => slot.id).sort()
  for (const id of IDS) {
    assert.deepEqual(Object.keys(derivedConfig(id).selections ?? {}).sort(), slots)
  }
})

test('a derived part is always a real part for that slot', () => {
  const config = derivedConfig('root')
  for (const [slot, partId] of Object.entries(config.selections ?? {})) {
    const part = assets.parts.find(candidate => candidate.id === partId)
    assert.ok(part, `${partId} is not a part in the asset set`)
    assert.equal(part.selectionSlot, slot)
  }
})

test('a saved avatar outranks the derived default', () => {
  const derived = derivedConfig('root')
  const saved = { selections: { head: 'hm1-p-000002' }, colors: { skin: 'AABBCC' } }
  const effective = effectiveConfig('root', saved)
  assert.equal(effective.selections?.head, 'hm1-p-000002')
  assert.equal(effective.colors?.skin, 'AABBCC')
  // Slots the user never touched still come from their derived default, so a
  // partial save is not a half-drawn person.
  assert.equal(effective.selections?.body, derived.selections?.body)
  assert.equal(effective.colors?.hair, derived.colors?.hair)
})

test('no saved avatar means the derived default, unchanged', () => {
  assert.deepEqual(effectiveConfig('root', null), derivedConfig('root'))
  assert.deepEqual(effectiveConfig('root', undefined), derivedConfig('root'))
})

test('a saved background is carried through, and absent means no override', () => {
  assert.equal(effectiveConfig('root', { background: 'transparent' }).background, 'transparent')
  assert.equal('background' in effectiveConfig('root', {}), false)
})
