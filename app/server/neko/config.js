const MIN_SECRET_LENGTH = 16

function parseBool(value) {
  return value === 'true' || value === '1'
}

function parseIdleTimeout(value) {
  if (value === undefined || value === '') return 300_000
  const parsed = Number(value)
  return Number.isNaN(parsed) ? 300_000 : parsed
}

function parseRecreateMode(value) {
  return value === 'noop' ? 'noop' : 'ssh'
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
    recreateMode: parseRecreateMode(process.env.NEKO_RECREATE_MODE),
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
  }
  if (config.recreateMode === 'ssh') {
    requiredVars.NEKO_SSH_HOST = config.sshHost
    requiredVars.NEKO_SSH_KEY_PATH = config.sshKeyPath
  }
  for (const [name, value] of Object.entries(requiredVars)) {
    if (!value) throw new Error(`neko config: ${name} is required when NEKO_ENABLED=true`)
  }

  if (!validUrlProtocol(config.internalUrl, ['http:', 'https:'])) {
    throw new Error('neko config: NEKO_INTERNAL_URL must be a valid http(s) URL')
  }
  // Accept either an absolute ws(s) URL or a same-origin relative path
  // (e.g. "/neko") — the latter lets the client derive ws(s) from its own
  // page origin, which is what a plain-http local demo needs.
  const publicWsIsRelativePath = config.publicWs.startsWith('/')
  if (!publicWsIsRelativePath && !validUrlProtocol(config.publicWs, ['ws:', 'wss:'])) {
    throw new Error('neko config: NEKO_PUBLIC_WS must be a valid ws(s) URL or an absolute path')
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
