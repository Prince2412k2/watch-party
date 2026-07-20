const MIN_SECRET_LENGTH = 16

function parseBool(value) {
  return value === 'true' || value === '1'
}

function parseIdleTimeout(value) {
  if (value === undefined || value === '') return 300_000
  const parsed = Number(value)
  return Number.isNaN(parsed) ? 300_000 : parsed
}

export function nekoConfig() {
  return {
    enabled: parseBool(process.env.NEKO_ENABLED),
    concurrencyEnabled: parseBool(process.env.NEKO_CONCURRENCY_ENABLED),
    internalUrl: process.env.NEKO_INTERNAL_URL || '',
    publicWs: process.env.NEKO_PUBLIC_WS || '',
    apiToken: process.env.NEKO_API_TOKEN || '',
    userPassword: process.env.NEKO_USER_PASSWORD || '',
    idleTimeoutMs: parseIdleTimeout(process.env.NEKO_IDLE_TIMEOUT_MS),
    cookieName: 'NEKO_SESSION',
    sshHost: process.env.NEKO_SSH_HOST || '',
    sshKeyPath: process.env.NEKO_SSH_KEY_PATH || '',
    usernameSecret: process.env.NEKO_USERNAME_SECRET || '',
  }
}

export function assertNekoEnabled() {
  if (!nekoConfig().enabled) throw new Error('neko disabled')
}

function validUrlProtocol(value, protocols) {
  try {
    const url = new URL(value)
    return protocols.includes(url.protocol)
  } catch {
    return false
  }
}

export function validateNekoConfig() {
  const config = nekoConfig()
  if (!config.enabled) return

  const requiredVars = {
    NEKO_API_TOKEN: config.apiToken,
    NEKO_USER_PASSWORD: config.userPassword,
    NEKO_USERNAME_SECRET: config.usernameSecret,
    NEKO_INTERNAL_URL: config.internalUrl,
    NEKO_SSH_HOST: config.sshHost,
    NEKO_SSH_KEY_PATH: config.sshKeyPath,
  }
  for (const [name, value] of Object.entries(requiredVars)) {
    if (!value) throw new Error(`neko config: ${name} is required when NEKO_ENABLED=true`)
  }

  if (!validUrlProtocol(config.internalUrl, ['http:', 'https:'])) {
    throw new Error('neko config: NEKO_INTERNAL_URL must be a valid http(s) URL')
  }
  if (!validUrlProtocol(config.publicWs, ['ws:', 'wss:'])) {
    throw new Error('neko config: NEKO_PUBLIC_WS must be a valid ws(s) URL')
  }
  if (!(config.idleTimeoutMs > 0)) {
    throw new Error('neko config: NEKO_IDLE_TIMEOUT_MS must be positive')
  }

  const secrets = { NEKO_API_TOKEN: config.apiToken, NEKO_USER_PASSWORD: config.userPassword, NEKO_USERNAME_SECRET: config.usernameSecret }
  for (const [name, value] of Object.entries(secrets)) {
    if (value.length < MIN_SECRET_LENGTH) {
      throw new Error(`neko config: ${name} must be at least ${MIN_SECRET_LENGTH} characters`)
    }
  }
}
