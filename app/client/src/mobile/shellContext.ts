import { createContext, useContext } from 'react'

interface MobileShell {
  openJoin: () => void
  path?: string
  /** True when this member is mirroring somebody else's shared browsing, so the
   *  screen shows the shared position and its own controls are inert. */
  following?: boolean
}

// Shared shell context. Screens read `openJoin` (raise the start/join sheet), the
// current `path`, and whether they are following a driver from here. Kept in its
// own module so screens can import it without a circular dependency on
// MobileApp.tsx. Navigation uses the router:
//   import { navigate } from '../../router'
export const ShellContext = createContext<MobileShell>({ openJoin: () => {}, path: '/', following: false })

export function useMobileShell() {
  return useContext(ShellContext)
}
