import { useEffect, useRef } from 'react'

/**
 * Warm the artwork that is about to slide under the cursor.
 *
 * `railWindow(...).prefetch` names the indices just outside the rail's window;
 * `prefetchTargets` turns them into URLs. This puts those URLs in the browser's
 * cache before they are asked for, so a step is a translate rather than a
 * translate followed by a fetch and a decode.
 *
 * Both mechanisms, because they fail in different places. `<link rel="prefetch">`
 * is the one the browser schedules at idle priority and the one a network trace
 * will attribute correctly; `new Image()` is what actually gets the bitmap
 * decoded, and it is the one that works in the WebKit view the desktop shell
 * runs, where `prefetch` is not implemented. Neither renders anything, so a URL
 * that 404s costs a cached negative response and nothing else.
 *
 * The `seen` set is per-mount and never pruned on purpose: it is a few hundred
 * short strings across a whole browsing session, and forgetting an entry would
 * re-issue a request the browser has already satisfied.
 */
export function useArtworkWarm(urls: readonly string[]): void {
  const seen = useRef(new Set<string>())
  const tags = useRef<HTMLLinkElement[]>([])

  useEffect(() => {
    for (const url of urls) {
      if (seen.current.has(url)) continue
      seen.current.add(url)

      const link = document.createElement('link')
      link.rel = 'prefetch'
      link.as = 'image'
      link.href = url
      document.head.appendChild(link)
      tags.current.push(link)

      const image = new Image()
      image.decoding = 'async'
      image.src = url
    }
    // Deliberately keyed on the joined list rather than the array identity: the
    // caller derives it fresh every render, and an identity dependency would
    // re-run this on every keystroke that touches unrelated state.
  }, [urls.join('|')])

  // Only on unmount. Removing a hint the moment the window moves on can cancel
  // the very request it just scheduled — which is precisely the fetch the next
  // step is about to need.
  useEffect(() => {
    const created = tags.current
    return () => {
      for (const link of created) link.remove()
      created.length = 0
    }
  }, [])
}
