#!/usr/bin/env node
// Emits the React and Flutter token surfaces from analog-tokens.json.
//
// Run from the repo root:  node app/shared/design/generate.mjs
//
// The three generated files are checked in, and a parity test in EACH language
// re-runs this transform and asserts the checked-in bytes match. So a hand-edit
// to a generated file, or a token change without a regenerate, fails the suite
// in both clients rather than drifting silently.
//
// Key-suffix conventions (see README.md):
//   value "#..."  -> colour        #RRGGBB or #RRGGBBAA
//   *Ms           -> duration      integer milliseconds
//   *Ease         -> cubic bezier   [x1, y1, x2, y2]
//   *Px           -> css px length
//   *Pct          -> percentage    0..100
//   *Deg          -> degrees
//   anything else -> unitless number or raw string

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..', '..', '..')
const SOURCE = join(HERE, 'analog-tokens.json')

export const OUTPUTS = {
  ts: 'app/client/src/design/analogTokens.ts',
  css: 'app/client/src/design/analog.css',
  dart: 'flutter_app/lib/ui/analog_tokens.dart',
}

/** Dart `int` rather than `double`. Everything else numeric is a double. */
const INT_KEYS = new Set(['toastMaxStack', 'aspectW', 'aspectH'])
const INT_GROUPS = new Set(['z'])

const BANNER_LINES = [
  'GENERATED FILE — DO NOT EDIT.',
  '',
  'Source:    app/shared/design/analog-tokens.json',
  'Generator: node app/shared/design/generate.mjs',
  '',
  'Edit the JSON and regenerate. A parity test in each client re-runs the',
  'generator and compares against these bytes, so hand-edits fail the suite.',
]

const isMeta = (key) => key.startsWith('$')
const isColor = (value) => typeof value === 'string' && value.startsWith('#')
const isEase = (key, value) => key.endsWith('Ease') && Array.isArray(value)
const suffix = (key) =>
  ['Ms', 'Px', 'Pct', 'Deg'].find((unit) => key.endsWith(unit)) ?? null

const kebab = (key) => key.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()
const pascal = (key) => key.charAt(0).toUpperCase() + key.slice(1)

/** Entries of one group, metadata keys dropped, source order preserved. */
const entriesOf = (group) =>
  Object.entries(group).filter(([key]) => !isMeta(key))

const groupsOf = (tokens) =>
  Object.entries(tokens).filter(([key, value]) => !isMeta(key) && typeof value === 'object')

// ── colour helpers ──────────────────────────────────────────────────────────

/** "#RRGGBB" | "#RRGGBBAA" -> { r, g, b, a } with a in 0..255. */
function parseColor(hex) {
  const body = hex.slice(1)
  if (body.length !== 6 && body.length !== 8) {
    throw new Error(`colour must be #RRGGBB or #RRGGBBAA, got "${hex}"`)
  }
  const int = (at) => parseInt(body.slice(at, at + 2), 16)
  return {
    r: int(0),
    g: int(2),
    b: int(4),
    a: body.length === 8 ? int(6) : 255,
  }
}

const dartColor = (hex) => {
  const { r, g, b, a } = parseColor(hex)
  const byte = (n) => n.toString(16).toUpperCase().padStart(2, '0')
  return `Color(0x${byte(a)}${byte(r)}${byte(g)}${byte(b)})`
}

// ── per-target value rendering ──────────────────────────────────────────────

function cssValue(key, value) {
  if (isColor(value)) return value
  if (isEase(key, value)) return `cubic-bezier(${value.join(', ')})`
  if (typeof value === 'string') return value
  switch (suffix(key)) {
    case 'Ms': return `${value}ms`
    case 'Px': return `${value}px`
    case 'Pct': return `${value}%`
    case 'Deg': return `${value}deg`
    default: return String(value)
  }
}

function tsValue(key, value) {
  if (isEase(key, value)) return `[${value.join(', ')}]`
  if (typeof value === 'string') return JSON.stringify(value)
  return String(value)
}

function dartValue(groupName, key, value) {
  if (isColor(value)) return dartColor(value)
  if (isEase(key, value)) return `Cubic(${value.map(dartDouble).join(', ')})`
  if (typeof value === 'string') return JSON.stringify(value)
  if (key.endsWith('Ms')) return `Duration(milliseconds: ${value})`
  if (INT_KEYS.has(key) || INT_GROUPS.has(groupName)) return String(value)
  return dartDouble(value)
}

const dartDouble = (n) => (Number.isInteger(n) ? `${n}.0` : String(n))

function dartType(groupName, key, value) {
  if (isColor(value)) return 'Color'
  if (isEase(key, value)) return 'Cubic'
  if (typeof value === 'string') return 'String'
  if (key.endsWith('Ms')) return 'Duration'
  if (INT_KEYS.has(key) || INT_GROUPS.has(groupName)) return 'int'
  return 'double'
}

// ── emitters ────────────────────────────────────────────────────────────────

const comment = (prefix) => BANNER_LINES.map((line) => (line ? `${prefix} ${line}` : prefix)).join('\n')

export function renderCss(tokens) {
  const blocks = groupsOf(tokens).map(([groupName, group]) => {
    const about = group.$about ? `  /* ${wrap(group.$about, 72, '     ')} */\n` : ''
    const lines = entriesOf(group)
      .map(([key, value]) => `  --an-${kebab(groupName)}-${kebab(key)}: ${cssValue(key, value)};`)
      .join('\n')
    return `${about}${lines}`
  })
  return `${comment('/*')}\n*/\n\n:root {\n${blocks.join('\n\n')}\n}\n`
}

export function renderTs(tokens) {
  const blocks = groupsOf(tokens).map(([groupName, group]) => {
    const about = group.$about ? `  /** ${wrap(group.$about, 74, '   *  ')} */\n` : ''
    const lines = entriesOf(group)
      .map(([key, value]) => `    ${key}: ${tsValue(key, value)},`)
      .join('\n')
    return `${about}  ${groupName}: {\n${lines}\n  },`
  })
  return [
    comment('//'),
    '',
    'export const analogTokens = {',
    blocks.join('\n\n'),
    '} as const',
    '',
    'export type AnalogTokens = typeof analogTokens',
    '',
    '/** `[x1, y1, x2, y2]` -> a CSS `cubic-bezier(...)` string. */',
    'export const ease = (curve: readonly [number, number, number, number]): string =>',
    '  `cubic-bezier(${curve.join(", ")})`',
    '',
  ].join('\n')
}

export function renderDart(tokens) {
  const blocks = groupsOf(tokens).map(([groupName, group]) => {
    const about = group.$about ? `/// ${wrap(group.$about, 74, '/// ')}\n` : ''
    const lines = entriesOf(group)
      .map(([key, value]) =>
        `  static const ${dartType(groupName, key, value)} ${key} = ${dartValue(groupName, key, value)};`)
      .join('\n')
    return `${about}abstract final class Analog${pascal(groupName)} {\n${lines}\n}`
  })
  return [
    comment('//'),
    '',
    // animation.dart carries Cubic and re-exports painting.dart's Color, so it
    // alone covers every type the emitters produce.
    "import 'package:flutter/animation.dart';",
    '',
    blocks.join('\n\n'),
    '',
  ].join('\n')
}

/** Soft-wrap an $about string so generated comments stay inside 80 columns. */
function wrap(text, width, indent) {
  const words = text.split(/\s+/)
  const lines = []
  let line = ''
  for (const word of words) {
    if (line && line.length + word.length + 1 > width) {
      lines.push(line)
      line = word
    } else {
      line = line ? `${line} ${word}` : word
    }
  }
  if (line) lines.push(line)
  return lines.join(`\n${indent}`)
}

// ── entry point ─────────────────────────────────────────────────────────────

export function readTokens() {
  return JSON.parse(readFileSync(SOURCE, 'utf8'))
}

export function renderAll(tokens = readTokens()) {
  return {
    [OUTPUTS.ts]: renderTs(tokens),
    [OUTPUTS.css]: renderCss(tokens),
    [OUTPUTS.dart]: renderDart(tokens),
  }
}

const invokedDirectly =
  process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]

if (invokedDirectly) {
  for (const [relative, contents] of Object.entries(renderAll())) {
    const target = join(ROOT, relative)
    mkdirSync(dirname(target), { recursive: true })
    writeFileSync(target, contents)
    process.stdout.write(`wrote ${relative}\n`)
  }
}
