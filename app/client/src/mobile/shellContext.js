import { createContext, useContext } from 'react'

// Shared shell context. Screens read `openJoin` (raise the start/join sheet) and
// the current `path` from here. Kept in its own module so screens can import it
// without a circular dependency on MobileApp.jsx. Navigation uses the router:
//   import { navigate } from '../../router.js'
export const ShellContext = createContext({ openJoin: () => {}, path: '/' })

export function useMobileShell() {
  return useContext(ShellContext)
}
