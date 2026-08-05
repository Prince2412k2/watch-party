import { createHmac, randomBytes, timingSafeEqual } from 'crypto'
import { db } from '../db.js'

export const PICKER_LEASE_TTL_MS = 30 * 60 * 1000
const TERMINAL_RETENTION_MS = 60 * 60 * 1000
const MAX_ACTIVE_LEASES_PER_USER = 20

db.exec(`
  CREATE TABLE IF NOT EXISTS servarr_picker_leases (
    id TEXT PRIMARY KEY,
    operation_id TEXT NOT NULL,
    service TEXT NOT NULL,
    record_id INTEGER,
    user_id TEXT NOT NULL,
    owner INTEGER NOT NULL DEFAULT 0,
    state TEXT NOT NULL,
    terminal_action TEXT,
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(user_id, service, operation_id)
  );
  CREATE INDEX IF NOT EXISTS servarr_picker_record_idx
    ON servarr_picker_leases(service, record_id, state);
`)

const selectOperation = db.prepare(`
  SELECT * FROM servarr_picker_leases
  WHERE user_id = ? AND service = ? AND operation_id = ?
`)
const selectLease = db.prepare('SELECT * FROM servarr_picker_leases WHERE id = ?')
const insertLease = db.prepare(`
  INSERT INTO servarr_picker_leases
    (id, operation_id, service, record_id, user_id, owner, state, expires_at, created_at, updated_at)
  VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?)
`)
const activateLease = db.prepare(`
  UPDATE servarr_picker_leases
  SET record_id = ?, owner = ?, state = 'active', updated_at = ?
  WHERE id = ? AND state = 'opening'
`)
const deleteOpeningLease = db.prepare("DELETE FROM servarr_picker_leases WHERE id = ? AND state = 'opening'")
const selectActiveCount = db.prepare(`
  SELECT COUNT(*) AS count FROM servarr_picker_leases
  WHERE user_id = ? AND state IN ('opening', 'active', 'cancel_pending', 'grabbing', 'cancelling') AND expires_at > ?
`)
const selectOtherActiveCount = db.prepare(`
  SELECT COUNT(*) AS count FROM servarr_picker_leases
  WHERE service = ? AND record_id = ? AND id != ?
    AND state IN ('active', 'cancel_pending', 'grabbing', 'cancelling') AND expires_at > ?
`)
const selectRecordClaim = db.prepare(`
  SELECT id, state FROM servarr_picker_leases
  WHERE service = ? AND record_id = ?
    AND state IN ('grabbing', 'cancelling') AND expires_at > ?
  LIMIT 1
`)
const selectPendingOwner = db.prepare(`
  SELECT * FROM servarr_picker_leases
  WHERE service = ? AND record_id = ? AND owner = 1
    AND state = 'cancel_pending' AND expires_at > ?
  ORDER BY created_at LIMIT 1
`)
const markPending = db.prepare(`
  UPDATE servarr_picker_leases SET state = 'cancel_pending', updated_at = ?
  WHERE id = ? AND state = 'active'
`)
const closeLeaseStatement = db.prepare(`
  UPDATE servarr_picker_leases SET state = 'closed', terminal_action = 'closed', updated_at = ?
  WHERE id = ? AND owner = 0 AND state IN ('active', 'cancel_pending')
`)
const markGrabbing = db.prepare(`
  UPDATE servarr_picker_leases SET state = 'grabbing', updated_at = ?
  WHERE id = ? AND state IN ('active', 'cancel_pending')
`)
const restoreAfterGrab = db.prepare(`
  UPDATE servarr_picker_leases SET state = ?, updated_at = ?
  WHERE id = ? AND state = 'grabbing'
`)
const claimCancellation = db.prepare(`
  UPDATE servarr_picker_leases SET state = 'cancelling', updated_at = ?
  WHERE id = ? AND owner = 1 AND state = 'cancel_pending'
`)
const restoreCancellation = db.prepare(`
  UPDATE servarr_picker_leases SET state = 'cancel_pending', updated_at = ?
  WHERE id = ? AND state = 'cancelling'
`)
const settleRecordStatement = db.prepare(`
  UPDATE servarr_picker_leases SET state = 'settled', terminal_action = ?, updated_at = ?
  WHERE service = ? AND record_id = ? AND state IN ('active', 'cancel_pending', 'grabbing', 'cancelling')
`)
const sweep = db.prepare(`
  DELETE FROM servarr_picker_leases
  WHERE expires_at <= ?
     OR (state IN ('closed', 'settled') AND updated_at <= ?)
`)

function leaseFromRow(row) {
  return row ? {
    id: row.id,
    operationId: row.operation_id,
    service: row.service,
    recordId: row.record_id,
    userId: row.user_id,
    owner: row.owner === 1,
    state: row.state,
    terminalAction: row.terminal_action,
    expiresAt: row.expires_at,
  } : null
}

function signingSecret() {
  return `${process.env.SESSION_SECRET || 'changeme'}:servarr-picker-v1`
}

function sign(encoded) {
  return createHmac('sha256', signingSecret()).update(encoded).digest('base64url')
}

export function sweepPickerLeases(now = Date.now()) {
  sweep.run(now, now - TERMINAL_RETENTION_MS)
}

function immediateTransaction(operation) {
  db.exec('BEGIN IMMEDIATE')
  try {
    const result = operation()
    db.exec('COMMIT')
    return result
  } catch (error) {
    db.exec('ROLLBACK')
    throw error
  }
}

export function beginPickerLease({ operationId, service, recordId = null, userId, now = Date.now(), ttlMs = PICKER_LEASE_TTL_MS }) {
  if (typeof operationId !== 'string' || !/^[A-Za-z0-9_-]{8,100}$/.test(operationId)) {
    throw Object.assign(new Error('valid operationId required'), { badRequest: true })
  }
  return immediateTransaction(() => {
    sweepPickerLeases(now)
    const existing = leaseFromRow(selectOperation.get(userId, service, operationId))
    if (existing) return { lease: existing, created: false }
    if (recordId != null && selectRecordClaim.get(service, recordId, now)) {
      throw Object.assign(new Error('record operation is settling'), { retryable: true })
    }
    if (Number(selectActiveCount.get(userId, now).count) >= MAX_ACTIVE_LEASES_PER_USER) {
      throw Object.assign(new Error('too many active picker operations'), { tooMany: true })
    }

    const id = randomBytes(32).toString('base64url')
    const state = recordId == null ? 'opening' : 'active'
    try {
      insertLease.run(id, operationId, service, recordId, userId, state, now + ttlMs, now, now)
    } catch (err) {
      if (!String(err?.message).includes('UNIQUE constraint failed')) throw err
      return { lease: leaseFromRow(selectOperation.get(userId, service, operationId)), created: false }
    }
    return { lease: leaseFromRow(selectLease.get(id)), created: true }
  })
}

export function activatePickerLease(id, recordId, owner, now = Date.now()) {
  return immediateTransaction(() => {
    if (selectRecordClaim.get(leaseFromRow(selectLease.get(id))?.service, recordId, now)) {
      throw Object.assign(new Error('record operation is settling'), { retryable: true })
    }
    activateLease.run(recordId, owner ? 1 : 0, now, id)
    return leaseFromRow(selectLease.get(id))
  })
}

export function abandonOpeningLease(id) {
  deleteOpeningLease.run(id)
}

export async function waitForPickerLease(id, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const lease = leaseFromRow(selectLease.get(id))
    if (!lease || lease.state !== 'opening') return lease
    await new Promise((resolve) => setTimeout(resolve, 25))
  }
  return leaseFromRow(selectLease.get(id))
}

export function pickerToken(lease) {
  const encoded = Buffer.from(JSON.stringify({
    v: 1,
    id: lease.id,
    service: lease.service,
    recordId: lease.recordId,
    userId: lease.userId,
    exp: lease.expiresAt,
  })).toString('base64url')
  return `${encoded}.${sign(encoded)}`
}

export function validatePickerToken(token, { service, recordId, userId, now = Date.now(), states = ['active', 'cancel_pending'] }) {
  if (typeof token !== 'string') return null
  const parts = token.split('.')
  if (parts.length !== 2) return null
  const [encoded, mac] = parts
  const expected = sign(encoded)
  const providedBytes = Buffer.from(mac)
  const expectedBytes = Buffer.from(expected)
  if (providedBytes.length !== expectedBytes.length || !timingSafeEqual(providedBytes, expectedBytes)) return null

  let claim
  try {
    claim = JSON.parse(Buffer.from(encoded, 'base64url').toString())
  } catch {
    return null
  }
  if (claim.v !== 1 || claim.service !== service || claim.recordId !== recordId ||
      claim.userId !== userId || typeof claim.exp !== 'number' || claim.exp <= now) return null
  const lease = leaseFromRow(selectLease.get(claim.id))
  if (!lease || lease.service !== service || lease.recordId !== recordId ||
      lease.userId !== userId || lease.expiresAt !== claim.exp) return null
  if (states && !states.includes(lease.state)) return null
  return lease
}

export function markPickerCancelPending(id, now = Date.now()) {
  markPending.run(now, id)
  return leaseFromRow(selectLease.get(id))
}

export function closePickerLease(id, now = Date.now()) {
  closeLeaseStatement.run(now, id)
  return leaseFromRow(selectLease.get(id))
}

export function markPickerGrabbing(id, now = Date.now()) {
  const before = leaseFromRow(selectLease.get(id))
  const changed = markGrabbing.run(now, id)
  return { before, claimed: changed.changes === 1, lease: leaseFromRow(selectLease.get(id)) }
}

export function restorePickerAfterGrab(id, state, now = Date.now()) {
  restoreAfterGrab.run(state, now, id)
}

export function claimPickerCancellation(id, now = Date.now()) {
  return claimCancellation.run(now, id).changes === 1
}

export function restorePickerCancellation(id, now = Date.now()) {
  restoreCancellation.run(now, id)
}

export function countOtherActivePickerLeases(lease, now = Date.now()) {
  return Number(selectOtherActiveCount.get(lease.service, lease.recordId, lease.id, now).count)
}

export function canRemovePickerRecord(lease, now = Date.now()) {
  return immediateTransaction(() => {
    const current = leaseFromRow(selectLease.get(lease.id))
    if (!current || current.state !== 'cancelling') return false
    return Number(selectOtherActiveCount.get(lease.service, lease.recordId, lease.id, now).count) === 0
  })
}

export function pendingPickerOwner(service, recordId, now = Date.now()) {
  return leaseFromRow(selectPendingOwner.get(service, recordId, now))
}

export function settlePickerRecord(service, recordId, action, now = Date.now()) {
  settleRecordStatement.run(action, now, service, recordId)
}
