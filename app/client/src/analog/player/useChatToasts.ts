// The chat-toast queue as a React hook.
//
// Drives `playerCore`'s toast queue from the party's chat log. The three-deep
// stack, the collapse count, the four-second-each expiry and the "nothing
// queues while the drawer is open" rule are all the shared core's; this hook
// feeds it and ticks it.

import { useEffect, useMemo, useRef, useState } from 'react'
import {
  expireToasts,
  newToastQueueState,
  pushToast,
  setChatOpen,
  toastView,
  type ToastQueueState,
  type ToastView,
} from '../playerCore.ts'
import {
  concealToasts,
  isFromOther,
  newMessages,
  nextToastDeadlineMs,
  shouldQueueMessages,
  toToastMessage,
  type ChatLike,
} from './toastFeed.ts'

export function useChatToasts({
  messages,
  chatOpen = false,
  selfUserId,
}: {
  messages: readonly ChatLike[]
  chatOpen?: boolean
  selfUserId?: string
}): ToastView {
  const [state, setState] = useState<ToastQueueState>(() => newToastQueueState(chatOpen))
  // Joining a party with scrollback must not fire a burst of toasts for history.
  const seenRef = useRef(messages.length)

  useEffect(() => {
    setState((current) => setChatOpen(current, chatOpen))
  }, [chatOpen])

  useEffect(() => {
    const { messages: arrivals, from } = newMessages(messages, seenRef.current)
    seenRef.current = messages.length
    if (arrivals.length === 0) return
    const now = Date.now()
    setState((current) => {
      if (!shouldQueueMessages(current, document.visibilityState)) return current
      let next = current
      arrivals.forEach((message, offset) => {
        if (!isFromOther(message, selfUserId)) return
        next = pushToast(next, toToastMessage(message, from + offset, now))
      })
      return next
    })
  }, [messages, selfUserId])

  // "Message content must not remain visible on a locked or backgrounded
  // device." Hiding the page empties the queue outright, and nothing queues
  // while hidden, so returning cannot replay what arrived with the screen off.
  useEffect(() => {
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') setState(concealToasts)
    }
    document.addEventListener('visibilitychange', onVisibility)
    return () => document.removeEventListener('visibilitychange', onVisibility)
  }, [])

  // Each toast runs its own four seconds, so the timer is always aimed at the
  // OLDEST one; expiring on the newest would strand the ones behind it.
  const deadline = nextToastDeadlineMs(state)
  useEffect(() => {
    if (deadline == null) return
    const timer = window.setTimeout(
      () => setState((current) => expireToasts(current, Date.now())),
      Math.max(0, deadline - Date.now()),
    )
    return () => window.clearTimeout(timer)
  }, [deadline])

  return useMemo(() => toastView(state), [state])
}
