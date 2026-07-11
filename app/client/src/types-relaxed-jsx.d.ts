import 'react'

declare global {
  namespace JSX {
    type LibraryManagedAttributes<C, P> = Partial<P>
  }
}

declare module 'react' {
  interface CSSProperties {
    [key: string]: any
  }
}

export {}
