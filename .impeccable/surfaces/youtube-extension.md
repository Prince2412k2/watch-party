# YouTube extension overlay

Mode: Operate. Scope: `app/client/extension/`, including the popup and floating frames.

## Confirmed interaction contract

Open chat and user feeds remain visible. Every other extension element disappears
after three seconds without mouse movement. Pointer or keyboard interaction restores
chrome. Closed chat uses an icon, not the word Chat. Real incoming unread messages
change that icon, add a count, and keep it visible while idle; reading chat clears it.
Hiding chrome must not unmount frames or reconnect room/media transports.

## Direction contract

THESIS: A private viewing companion that recedes into the video, replacing the
clunky collection of always-visible windows with a small playback/AV strip and
progressively disclosed party details.

OWN-WORLD: Blue-tinted charcoal, pale mint for active/readable actions, restrained
state color, regular Circular UI type, rounded but compact controls, minimal dividers.
Light mode uses the same hierarchy on a cool near-white ground.

STORY: Join a friend, watch together, speak or react; open party details only to
invite, manage people, or change settings.

FIRST VIEWPORT: Video dominates. Feeds float independently. A four-control strip
sits bottom-center; party access sits bottom-right. An icon-only closed chat launcher
sits top-right. Chat opens as a full-height right-side conversation with 12px
vertical insets; hidden-panel resize geometry is restored before opening. Preferences replace
party details rather than expanding a second settings wall beneath them.

FORM: Quiet cinema companion; code-led working UI. Reference: seed:55e325f22efc76a7.
The user's explicit idle/notification rules govern visibility and interaction.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish
review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
