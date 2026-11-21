---
version: 1
slug: "flutter-client-lib-ui-screens-home-screen-dart"
primary_target: "flutter_client/lib/ui/screens/home_screen.dart"
related_targets: ["flutter_client/lib/ui/screens/settings_screen.dart"]
---

# Home surface (WhisperDoc client window)

Scope: the 420×600 client window: home screen, its recording states, and the
Account and Settings panels it opens. Mode: Operate.

Audience and job: the broad public on Windows. They dictate from other apps
with the global hotkey; the window is opened to confirm readiness, repair a
problem, switch output style, recopy the last transcript, or change settings.

Constraints: crimson #DC143C on near-black, Lexend (bundled, not fetched),
fixed 420×600 client area, Flutter on Windows at 100% scale (no ClearType, no
hinting, so type must land on whole pixels).

## Direction contract

THESIS: The window is a dark screen whose one job is to show what was said,
like broadcast captions. It refuses the category default: a glowing round mic
button over a rounded transcript card with an icon toolbar.

OWN-WORLD: Ground #0B0A0C, caption band #26211F, white text, secondary
#A69DA0, rules #221E20, crimson #DC143C for record and "needs you" only, amber
#F2B640 only for "update available". Flat fills, 1px rules, 2px corner radius,
no gradients, glows, glass or soft shadows. Lexend in four sizes (12/17,
16/24, 20/29, 28/37; 16/30 for caption bands) with even leading, every
baseline on a whole pixel. One 1.5-stroke line-icon family.
Status speaks in caption cues: [ ready ], [ listening · 0:07 ],
[ can't connect ].

STORY: At a glance the visitor sees one cue and the shortcut, knows the app is
ready, and leaves. When something breaks, the cue turns crimson, says what
broke in plain words, and offers the one fix. The account indicator owns
connection, updates and diagnostics; Settings owns behaviour.

FIRST VIEWPORT: Title bar 40px: "WhisperDoc" 12/600 left; account indicator
(bare cloud or avatar with an 8px amber/crimson dot only when needed),
minimize, close right. Cue centred 64px below; "[Ctrl Q] to talk" 20/29 under
it. The last transcript set as a caption band near the bottom of the stage
with a tick, age and copy icon. Bottom bar 64px: crimson Record (40px, 2px
radius) left, output style (T Raw ⌄) beside it, History, Incognito, Settings
icons right. Recording: same screen; a 388×192 pixel block meter takes the
stage, scrolling at display refresh, coloured by column age in three flat
crimson tiers with a white peak cell; Stop replaces Record; other controls
lock behind a lock icon.

FORM: Captions (broadcast closed captions), IMPECCABLE'S PICK, rank 1 of 7.
seed:7bf19dbc17df7b03

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Signature interaction and motion

The pixel meter: one CustomPainter on its own layer, driven by a vsync Ticker
only while recording; samples from LevelNormalizer land in a fixed ring
buffer; the strip scrolls continuously between samples, snapped to device
pixels; blocks are batched into one path per colour tier. Everything else is
state swapped whole (no per-frame widget rebuilds, no pulsing decorations).

## Reference

Approved mockups: claude.ai canvas "WhisperDoc Home Redesign", pages R4
(home states, Account, Settings) and R6 (live meter). Rejected: R5 (full
crimson window, framed stage).

## Open decisions

- Account and Settings as full-window panels (mocked on canvas page R4);
  this build restyles the existing dialogs to the shared shell instead.
- Self-hosted backend mode: account panel shows sign-in identity instead of
  Groq key; same structure.

## Settled

- Icons: the bundled Lucide font, named in AppIcons (tree-shaken to the
  glyphs in use).
