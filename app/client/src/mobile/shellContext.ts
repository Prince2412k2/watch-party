import { createContext, useContext } from 'react'

export interface MobileShell {
  openJoin: () => void
  path?: string
}

// Shared shell context. Screens read `openJoin` (raise the start/join sheet) and
// the current `path` from here. Kept in its own module so screens can import it
// without a circular dependency on MobileApp.jsx. Navigation uses the router:
//   import { navigate } from '../../router'
export const ShellContext = createContext<MobileShell>({ openJoin: () => {}, path: '/' })

export function useMobileShell() {
  return useContext(ShellContext)
}
