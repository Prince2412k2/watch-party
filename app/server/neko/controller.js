import { controlStatus as defaultControlStatus } from './admin.js'
import { controllerUserFor as defaultControllerUserFor } from './lease.js'

export async function currentController(partyId, { controlStatus = defaultControlStatus, controllerUserFor = defaultControllerUserFor } = {}) {
  const status = await controlStatus()
  if (!status.hasHost || !status.hostSessionId) return null
  const userId = controllerUserFor(status.hostSessionId)
  if (!userId) return null
  return { userId, nekoSessionId: status.hostSessionId }
}

export async function isController(partyId, userId, deps = {}) {
  const controller = await currentController(partyId, deps)
  return Boolean(controller && controller.userId === userId)
}
