// The analog player control kit.
//
// Everything the redesigned player chrome is assembled from, over the shared
// interaction cores in ../playerCore.ts and the generated tokens in
// ../../design/analogTokens.ts. Components are presentational — they take state
// and callbacks, never a media element — so the media wiring stays in
// components/Player.tsx and every rule in here is testable without a renderer.

export { default as AnalogTimeline } from './AnalogTimeline.tsx'
export type { AnalogTimelineProps, TimelinePreview } from './AnalogTimeline.tsx'
export { default as AnalogVolume } from './AnalogVolume.tsx'
export type { AnalogVolumeProps } from './AnalogVolume.tsx'
export { default as AnalogToastStack } from './AnalogToastStack.tsx'
export type { AnalogToastStackProps } from './AnalogToastStack.tsx'
export { default as AnalogSettingsStack } from './AnalogSettingsStack.tsx'
export type { AnalogSettingsStackProps } from './AnalogSettingsStack.tsx'

export { useAutoHideControls } from './useAutoHideControls.ts'
export type { AutoHideControls } from './useAutoHideControls.ts'
export { useChatToasts } from './useChatToasts.ts'
export { useDisplayPreferences } from './useDisplayPreferences.ts'

export * from './timelineGeometry.ts'
export * from './volumeCore.ts'
export * from './toastFeed.ts'
export * from './autoHideWiring.ts'
export * from './chatShortcut.ts'
export * from './presentation.ts'
export * from './format.ts'
