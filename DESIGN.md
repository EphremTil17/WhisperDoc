---
name: WhisperDoc
description: A dark desktop window that shows what was said, set like broadcast captions.
colors:
  ground: "#0B0A0C"
  surface: "#171415"
  band: "#26211F"
  rule: "#221E20"
  outline: "#4A4245"
  text: "#FFFFFF"
  text-muted: "#A69DA0"
  icon-faint: "#6B6265"
  record: "#DC143C"
  alert: "#F2566F"
  update: "#F2B640"
  on-light: "#0B0A0C"
  meter-tip: "#FF9AAE"
  meter-bright: "#E7425F"
  meter-mid: "#A3203D"
  meter-dim: "#5A1121"
  meter-peak: "#FFFFFF"
typography:
  display:
    fontFamily: "Lexend"
    fontSize: "28px"
    fontWeight: 500
    lineHeight: "37px"
    fontFeature: "tnum"
  title:
    fontFamily: "Lexend"
    fontSize: "20px"
    fontWeight: 400
    lineHeight: "29px"
  body:
    fontFamily: "Lexend"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: "24px"
  caption-band:
    fontFamily: "Lexend"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: "30px"
  caption:
    fontFamily: "Lexend"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: "17px"
  label:
    fontFamily: "Lexend"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: "17px"
rounded:
  control: "2px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  button-record:
    backgroundColor: "{colors.record}"
    textColor: "{colors.text}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0 16px 0 14px"
    height: "40px"
  button-primary:
    backgroundColor: "{colors.text}"
    textColor: "{colors.on-light}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0 16px 0 14px"
    height: "40px"
  button-outline:
    backgroundColor: "transparent"
    textColor: "{colors.text}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0 16px 0 14px"
    height: "40px"
  button-unavailable:
    backgroundColor: "transparent"
    textColor: "{colors.text-muted}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0 16px 0 14px"
    height: "40px"
  icon-button:
    backgroundColor: "transparent"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.control}"
    size: "40px"
  icon-button-hover:
    backgroundColor: "{colors.band}"
    textColor: "{colors.text-muted}"
  caption-band:
    backgroundColor: "{colors.band}"
    textColor: "{colors.text}"
    typography: "{typography.caption-band}"
    padding: "3px 10px"
  keycap:
    backgroundColor: "{colors.band}"
    textColor: "{colors.text}"
    padding: "0 8px"
  dialog:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.control}"
    padding: "16px"
  input:
    backgroundColor: "{colors.ground}"
    textColor: "{colors.text}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
  dropdown-trigger:
    backgroundColor: "{colors.ground}"
    textColor: "{colors.text}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "40px"
  menu:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.control}"
    padding: "4px"
  menu-item-selected:
    backgroundColor: "{colors.band}"
    textColor: "{colors.text}"
  tooltip:
    backgroundColor: "{colors.band}"
    textColor: "{colors.text}"
    typography: "{typography.caption}"
    rounded: "{rounded.control}"
    padding: "4px 8px"
---

# Design System: WhisperDoc

## Overview

**Creative North Star: "Captions"**

The window is a dark screen whose one job is to show what was said, the way broadcast closed captions do. Text sits on solid caption bands over a near-black ground; status speaks as a bracketed sound description (`[ ready ]`, `[ listening · 0:07 ]`, `[ can't connect ]`); everything else stays out of the way. The window is fixed at 420×600 and is mostly glanced at, so each state is one cue, one line and at most one fix.

The material is flat and pixel-exact. Fills are solid, dividers are 1px, corners are 2px, and every text baseline lands on a whole device pixel, because Flutter on Windows draws text with greyscale antialiasing and no hinting. Colour is held back: white on near-black does the work, crimson appears only when recording or when the app needs the user, and amber only when an update is waiting. The one live, moving element is the recording meter, a scrolling grid of crimson pixel blocks; everything else changes by swapping whole states.

The system rejects the category default it was built against: a glowing round mic button over a rounded transcript card with an icon toolbar. No gradients, glows, glass or soft shadows.

**Key Characteristics:**
- Near-black ground, warm-dark caption bands, white text.
- Crimson for Record and "needs you" only; amber for "update available" only.
- Lexend on an integer-baseline scale, painted on whole pixels.
- Flat fills, 1px rules, 2px corners; depth by tone, never by shadow.
- One stroke-icon family (bundled Lucide, named in `AppIcons`).
- Bracketed caption cues carry status.

## Colors

A near-monochrome warm-dark palette with one rationed crimson and one rationed amber.

### Primary
- **Broadcast Crimson** (record): the brand crimson. Fills only: the Record and Stop buttons, the live dot in the listening cue, the account indicator's "needs you" dot, the close button's hover, and the text-selection handle (selection fill at 45% alpha). Never text, never a switch, never a selected state.
- **Readable Crimson** (alert): crimson lifted to 5.7:1 on ground so it can be text or a thin icon. Used for alert-tone caption cues (`[ not set up ]`, `[ can't connect ]`) and their leading icon.

### Secondary
- **Update Amber** (update): "update available" only, as the 8px dot on the account indicator and its update surfaces. Nothing else is amber.

### Neutral
- **Screen Black** (ground): window ground, input and dropdown-trigger fill, the text on light fills (on-light).
- **Raised Charcoal** (surface): anything that floats over the ground: dialogs, menus, snackbars.
- **Caption Brown** (band): caption bands, keycaps, tooltips, and the hover/pressed/selected surface for icon buttons and menu rows.
- **Hairline** (rule): every 1px divider and the border on dialogs, menus, snackbars and inputs.
- **Dashed Grey** (outline): dashed "unavailable" outlines, outline-button borders, switch track outline when off.
- **White** (text): primary text, primary-button fill, the "on" switch track.
- **Muted Rose-Grey** (text-muted): secondary text (7:1 on ground), cues in the muted tone, idle icons, section labels.
- **Faint Rose-Grey** (icon-faint): chevrons, locked and disabled icons, the "off" switch thumb. Below 4.5:1, so never text.

### Meter
- **Meter tiers** (meter-bright, meter-mid, meter-dim) colour the recording meter's column bodies by age, newest to oldest, in flat steps; **meter-tip** caps sounding columns in the newest band; **meter-peak** is the single white peak cell. These are part of "recording", so they sit inside the crimson rule.

### Named Rules
**The Crimson Means Record Rule.** Crimson fills mean "recording" or "this needs you". If a control is merely on, selected or active, it is white or band, never crimson.

**The One Amber Rule.** Amber marks "update available" and nothing else.

**The White Switch Rule.** An "on" switch is a white track with a ground-coloured thumb; off is a transparent track with an outline border and a faint thumb.

## Typography

**UI Font:** Lexend (bundled, never fetched)
**Mono Font:** JetBrains Mono, for logs and history text only

**Character:** Lexend's open, even forms read like caption lettering at small sizes; one family carries every role, separated by size and a single medium weight.

### Hierarchy
- **Display** (500, 28/37, tabular figures): the recording timer.
- **Title** (400, 20/29): headlines in blocked states and the main shortcut line (`[Ctrl Q] to talk`).
- **Body** (400, 16/24): body copy, values, button labels (set at 500), dialog titles (set at 600).
- **Caption Band** (400, 16/30): transcript text on caption bands; the extra leading makes room for the band's 3px vertical padding so stacked bands meet cleanly.
- **Caption** (400, 12/17): cues, meta (`just now`), tooltips, snackbars, keycaps (at 500), the title-bar wordmark (at 600).
- **Label** (500, 12/17, text-muted): section headings inside panels and settings.

### Named Rules
**The Whole-Pixel Baseline Rule.** Lexend's ascent is 1.0 em and descent 0.25 em; every size/line-height pair keeps (line height − 1.25 × size) even and uses even leading distribution, so the baseline falls on a whole pixel at 1×. Do not add a size or line height that breaks this. All UI text is drawn through `CrispText` (or a render object that snaps its paint origin, as `CaptionBand` does), which paints at the nearest device pixel. This is the fix for blurred text on Windows, where Flutter has no ClearType or hinting.

**The Four Sizes Rule.** 12, 16, 20 and 28. No 9.5, 10, 11, 13 or other in-between sizes.

## Layout

A fixed 420×600 frameless window, not responsive. A 40px title bar (wordmark left; account indicator, minimize, close right), a centred stage, and a 64px bottom bar separated by a 1px rule (Record and the output-style trigger left; History, Incognito, Settings icon buttons right). Status lives in the stage's upper third as a centred stack: cue, then a 20/29 line, then at most one fix button. The last transcript sits as caption bands near the bottom of the stage, with a tick, age and copy action beneath.

Spacing is a 4px grid (xs 4, sm 8, md 12, lg 16, xl 24, xxl 32). Window and dialog insets are 16px; controls are 40px tall and icon targets 40px square; icons are 18px (16px small, 14px in window buttons and cues). Recording uses the same layout: the pixel meter takes the stage, Stop replaces Record, and the other bottom-bar controls collapse behind a lock icon.

## Elevation & Depth

Flat. No shadows are drawn anywhere; where Material components take elevation it is zeroed or invisible, and surface tint is transparent. Depth is two tonal steps plus a hairline: ground (base), surface (anything floating) with a 1px rule border, band (caption, hover, pressed, selected).

### Named Rules
**The No-Glow Rule.** No gradients, glows, glass, blur or soft shadows. A floating thing is a surface fill with a 1px rule, nothing more.

## Shapes

Squared. One radius, 2px, on buttons, icon-button hover fills, dialogs, menus, menu rows, inputs, tooltips and snackbars; caption bands and keycaps are square-cornered rectangles. Circles exist only as status marks: the live record dot, the 8px account badge (with a 2px ground ring), and the switch. A disabled Record button keeps its mark as a crimson ring instead of a white dot. Unavailable controls get a 1px dashed outline (3px dash, 3px gap, outline colour) instead of a solid border; dashes land on whole pixels.

## Components

### Buttons (`AppButton`)
Flat, squared, 40px tall, label in body at 500 with an optional leading mark and an 8px gap; 14px start / 16px end padding. No ink splash; pressed overlay is the ink colour at 12%.
- **Record:** crimson fill, white ink. Start or stop recording only (a dot mark for Record, a square for Stop).
- **Primary:** white fill, ground-coloured ink. The one fix for a blocked state (`Add key`).
- **Outline:** transparent with a 1px outline border, white ink. Secondary actions beside a primary.
- **Unavailable:** any tone with no handler renders transparent, muted text, inside a `DashedOutline`.

### Icon Buttons and Window Buttons
Themed globally: 40px square, 18px icon, muted foreground, band fill on hover and press, faint when disabled, no splash. `WindowButton` (minimize, close) is 40×32 with a 14px icon; hover turns the icon white and the fill band, except close, which fills crimson on hover.

### Caption Band (`CaptionBand`)
The signature text treatment. Centred lines, each on its own solid band-coloured rectangle sized to that line's glyphs plus 10px horizontal and 3px vertical padding; up to three lines, ellipsised. Set in the caption-band style; band edges and the text origin are pixel-snapped.

### Caption Cue (`CaptionCue`)
Status in brackets, in caption size: `[ ready ]`. Three tones: muted (text-muted), alert (readable crimson, optional 14px leading icon), live (an 8px crimson dot before alert-coloured text).

### Keycap (`Keycap`)
A shortcut set on a band rectangle with 8px side padding, label at weight 500, at the size of the surrounding line (title in the shortcut line, caption elsewhere).

### Dialogs (`AppDialog`)
The one dialog shell: surface fill, 1px rule border, 2px radius, 16px inset from the window. 48px header with the title in body at 600 and a close icon button, a 1px rule under it, a body, and an optional footer above a 1px rule with 16px padding.

### Inputs and Dropdowns (`AppDropdown`, theme)
Inputs are ground-filled with a 1px rule border and 2px radius; focus shifts the border to text-muted; hints are muted body text. The dropdown trigger matches (ground fill, rule border, 40px, body text, chevron in muted/faint). Its menu is a surface panel with a rule border and 4px padding; rows are 2px-radius, muted by default, band-filled and white with a trailing check when selected.

### Switches
Per the White Switch Rule.

### Tooltips and Snackbars
Tooltips: band fill, caption text, 4px/8px padding, 400ms wait. Snackbars: floating, surface fill, rule border, caption text, 16px inset.

### Icons (`AppIcons`)
One 1.5-stroke line family: the bundled Lucide font, each glyph named in `AppIcons` so release builds tree-shake to the code points in use. Add icons by adding a named constant there.

### Pixel Meter (`PixelMeter`)
The recording meter: 6px square blocks on an 8px pitch, mirrored about a centre row, scrolling continuously at display refresh on its own repaint layer (a vsync ticker, no widget rebuilds). Column bodies are coloured by age in flat tiers (bright under 10 columns old, mid under 26, then dim); sounding columns in the bright zone are capped with a light tip cell, silence never reads brighter, and a single white peak cell rides the newest column. One draw call per tier. Runs only while recording.

### Motion
State swaps (hover, focus, panel open) take 120ms with ease-out cubic. Nothing pulses or animates decoratively; apart from the meter, states change whole.

## Do's and Don'ts

### Do:
- **Do** draw every UI string with `CrispText` (or a pixel-snapping render object) in an `AppType` style.
- **Do** keep crimson for Record/Stop, the live dot and "needs you"; use readable crimson (alert) when it must be text or a thin icon.
- **Do** float things on surface with a 1px rule border, and use band for hover, pressed and selected.
- **Do** say status as a bracketed caption cue, and give every blocked state its one fix as a primary button.
- **Do** mark unavailable controls with the dashed outline rather than lowering opacity.
- **Do** take every colour, size, space, radius and duration from `app_tokens.dart` and every icon from `AppIcons`.

### Don't:
- **Don't** use gradients, glows, glass, blur or soft shadows, or non-zero Material elevation.
- **Don't** colour switches, chips or selected states crimson; "on" is white.
- **Don't** use amber for anything but "update available".
- **Don't** add font sizes or line heights outside 12/17, 16/24, 16/30, 20/29, 28/37.
- **Don't** use Material `Icons.*` or any second icon family.
- **Don't** round corners past 2px or use pill shapes.
- **Don't** set icon-faint as text; it is below 4.5:1.
