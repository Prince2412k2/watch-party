// Pairing credentials are available to extension pages, not content scripts.
chrome.storage.local.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' })
chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' })
})
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message?.type === 'watchparty-context') respond({ tabId: sender.tab?.id ?? null })
  if (message?.type === 'watchparty-open-setup') {
    chrome.action.openPopup().then(() => respond({ ok: true }), () => respond({ error: 'Click the Watch Party toolbar button to open setup.' }))
    return true
  }
})
