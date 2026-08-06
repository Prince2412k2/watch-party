import type { BrowseEntry, PartyBrowse } from '../types.ts'
import type { BrowseTab } from '../partyAuthority.ts'
import type { MobileItem } from './types.ts'

/**
 * Shared-browsing translation for the phone tree.
 *
 * `session.browse` is the canonical shared browsing state — the same record the
 * desktop Library drives and follows. The phone screens previously ignored it
 * entirely, so a guest on a phone watched their own library while the host drove
 * theirs. These are the pure translations between that wire record and the phone
 * presentation (which shows library drill-downs in a bottom sheet instead of a
 * full-page grid), kept side-effect free so the follow/publish rules are
 * testable without React.
 */

/** The canonical tab a phone route publishes. Home covers both library tabs. */
export function tabForMobilePath(path: string | undefined, libraryTab: BrowseTab = 'movies'): BrowseTab | null {
  if (path === '/discover') return 'discover'
  if (path === '/downloads') return 'downloads'
  if (path === '/movies') return 'movies'
  if (path === '/series') return 'series'
  // '/library' and '/' both land on Home, which stands in for the library tab.
  if (path === '/library' || path === '/' || path === undefined) return libraryTab
  return null
}

/** Wire stack → the phone detail sheet's drill-in stack. Entries the server
 *  cannot identify (no id) are dropped rather than rendered as a blank sheet. */
export function sheetStackFromBrowse(browse: PartyBrowse | null | undefined): MobileItem[] {
  const stack = browse?.stack
  if (!Array.isArray(stack)) return []
  const items: MobileItem[] = []
  for (const entry of stack) {
    const id = typeof entry?.id === 'string' ? entry.id : null
    if (!id) continue
    items.push({
      Id: id,
      Name: typeof entry.name === 'string' ? entry.name : '',
      Type: typeof entry.type === 'string' ? entry.type : 'Folder',
      SeriesId: typeof entry.seriesId === 'string' ? entry.seriesId : undefined,
      SeriesName: typeof entry.seriesName === 'string' ? entry.seriesName : undefined,
    })
  }
  return items
}

/** Phone detail sheet stack → the wire shape the desktop Library also speaks. */
export function browseStackFromSheet(stack: MobileItem[]): BrowseEntry[] {
  return stack.map((item) => ({
    id: item.Id,
    name: item.Name,
    type: item.Type,
    ...(item.SeriesId ? { seriesId: item.SeriesId } : {}),
    ...(item.SeriesName ? { seriesName: item.SeriesName } : {}),
  }))
}

/** The view patch a driver publishes for its current sheet stack. An empty stack
 *  means the driver closed the sheet and is back on the rails ('grid'). */
export function viewPatchForSheet(stack: MobileItem[]): Partial<PartyBrowse> {
  const root = stack[0]
  const leaf = stack[stack.length - 1]
  if (!root || !leaf) return { screen: 'grid', mediaId: null, episodeId: null }
  return {
    screen: 'detail',
    mediaId: root.Id,
    episodeId: leaf.Id === root.Id ? null : leaf.Id,
  }
}
