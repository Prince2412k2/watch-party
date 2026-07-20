import test from 'node:test'
import assert from 'node:assert/strict'

const { nekoConfig, assertNekoEnabled, validateNekoConfig } = await import('./config.js')

const NEKO_VARS = [
  'NEKO_ENABLED', 'NEKO_CONCURRENCY_ENABLED', 'NEKO_INTERNAL_URL', 'NEKO_PUBLIC_WS',
  'NEKO_API_TOKEN', 'NEKO_USER_PASSWORD', 'NEKO_IDLE_TIMEOUT_MS', 'NEKO_SSH_HOST',
  'NEKO_SSH_KEY_PATH', 'NEKO_USERNAME_SECRET',
]

function withEnv(overrides, fn) {
  const saved = {}
  for (const key of NEKO_VARS) saved[key] = process.env[key]
  for (const key of NEKO_VARS) delete process.env[key]
  Object.assign(process.env, overrides)
  try {
    fn()
  } finally {
    for (const key of NEKO_VARS) {
      if (saved[key] === undefined) delete process.env[key]
      else process.env[key] = saved[key]
    }
  }
}

const validEnv = {
  NEKO_ENABLED: 'true',
  NEKO_API_TOKEN: 'a'.repeat(20),
  NEKO_USER_PASSWORD: 'b'.repeat(20),
  NEKO_USERNAME_SECRET: 'c'.repeat(20),
  NEKO_INTERNAL_URL: 'http://neko.internal:8080',
  NEKO_PUBLIC_WS: 'wss://public.example.com/neko/api/ws',
  NEKO_SSH_HOST: 'contab',
  NEKO_SSH_KEY_PATH: '/keys/neko',
}

test('disabled by default; validateNekoConfig no-ops', () => {
  withEnv({}, () => {
    const config = nekoConfig()
    assert.equal(config.enabled, false)
    assert.doesNotThrow(() => validateNekoConfig())
    assert.throws(() => assertNekoEnabled(), /neko disabled/)
  })
})

test('NEKO_ENABLED=false is disabled', () => {
  withEnv({ NEKO_ENABLED: 'false' }, () => {
    assert.equal(nekoConfig().enabled, false)
  })
})

test('idle timeout override and default', () => {
  withEnv({}, () => {
    assert.equal(nekoConfig().idleTimeoutMs, 300_000)
  })
  withEnv({ NEKO_IDLE_TIMEOUT_MS: '1000' }, () => {
    assert.equal(nekoConfig().idleTimeoutMs, 1000)
  })
})

test('concurrency flag parsed but reserved', () => {
  withEnv({ NEKO_CONCURRENCY_ENABLED: 'true' }, () => {
    assert.equal(nekoConfig().concurrencyEnabled, true)
  })
  withEnv({}, () => {
    assert.equal(nekoConfig().concurrencyEnabled, false)
  })
})

test('enabled + valid config does not throw', () => {
  withEnv(validEnv, () => {
    assert.doesNotThrow(() => validateNekoConfig())
  })
})

test('enabled + missing required var throws', () => {
  for (const key of ['NEKO_API_TOKEN', 'NEKO_USER_PASSWORD', 'NEKO_USERNAME_SECRET', 'NEKO_INTERNAL_URL', 'NEKO_SSH_HOST', 'NEKO_SSH_KEY_PATH']) {
    withEnv({ ...validEnv, [key]: '' }, () => {
      assert.throws(() => validateNekoConfig(), new RegExp(key))
    })
  }
})

test('enabled + bad internal url protocol throws', () => {
  withEnv({ ...validEnv, NEKO_INTERNAL_URL: 'ftp://neko.internal' }, () => {
    assert.throws(() => validateNekoConfig(), /NEKO_INTERNAL_URL/)
  })
})

test('enabled + bad public ws protocol throws', () => {
  withEnv({ ...validEnv, NEKO_PUBLIC_WS: 'http://public.example.com' }, () => {
    assert.throws(() => validateNekoConfig(), /NEKO_PUBLIC_WS/)
  })
})

test('enabled + non-positive idle timeout throws', () => {
  withEnv({ ...validEnv, NEKO_IDLE_TIMEOUT_MS: '0' }, () => {
    assert.throws(() => validateNekoConfig(), /NEKO_IDLE_TIMEOUT_MS/)
  })
  withEnv({ ...validEnv, NEKO_IDLE_TIMEOUT_MS: '-5' }, () => {
    assert.throws(() => validateNekoConfig(), /NEKO_IDLE_TIMEOUT_MS/)
  })
})

test('enabled + weak secret throws', () => {
  withEnv({ ...validEnv, NEKO_API_TOKEN: 'short' }, () => {
    assert.throws(() => validateNekoConfig(), /NEKO_API_TOKEN/)
  })
})
