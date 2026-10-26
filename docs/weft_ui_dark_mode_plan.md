# Plan: dark mode for `weft_ui`

The first item in [the weft_ui plan](weft_ui_plan.md)'s "Not in v1": a dark set of the colour
tokens, a way for a page to follow the system's choice or force one, and the demo apps' palettes in
dark versions, with every tone's contrast checked in both.

## Status

Draft, for review. Nothing is built. The questions are under "Decisions", each with a
recommendation.

## What's there now

- **Every colour a component draws is a token** (`WeftUi.Tokens`), named for its purpose (`surface`,
  `fgMuted`, `dangerSoftFg`), with its default declared on `:where(:root)`, so an app's value wins.
  v1 named them this way so another theme would need no component changes.
- **A few colours aren't tokens:**
  - The `Switch` thumb is `white`.
  - A dialog's `::backdrop` is `rgb(0 0 0 / 0.4)`.
  - The shadows are black at a fixed opacity.
  - `transparent` borders are fine as they are.
- **The native controls** (`Checkbox` and `RadioGroup` through `accentColor`, the `Select` popup,
  scrollbars, the date and number inputs) are drawn by the browser. They follow the page's
  `color-scheme`, which nothing sets yet.
- **The tokens already use a media query.** The reduced-motion durations are a `Css.global` on
  `:where(:root)` with a `media` block. That's one way to do dark mode.
- **The apps set their palettes on `:root`, light only:**
  - weft_notes sets 15 tokens.
  - weft_shop sets 20, and also has hard-coded colours of its own: the hero gradients, the
    placeholder stripes, the gallery's white caption, the rail's white cards and the sale badge's
    white text.

## Design

### 1. The dark values: `light-dark()`, not a second block of variables

Each colour token's default becomes a pair: `Css.var("light-dark(#ffffff, #09090b)")`. The browser
picks one by the `color-scheme` of the element where the colour is used, so:

- **Opting in or forcing a theme is setting `color-scheme`.** `light dark` follows the system,
  `dark` forces dark, `light` forces light, and `color-scheme` is inherited, so this works on any
  subtree too (a dark header on a light page, or a preview in the gallery). There's no
  `[data-theme]` selector to add to every token.
- **The native controls come along.** `color-scheme` is also what makes the browser draw checkboxes,
  selects, scrollbars and inputs dark, so they match the components.
- **Nothing changes until an app opts in.** An element's `color-scheme` is `normal` unless something
  sets it, and `normal` picks the light value. Existing pages look exactly as they do now.
- **An app's own values can be pairs too:** `(Tokens.accent, "light-dark(#9a4b22, #e0915f)")`. A
  plain value is used in both schemes, which is right for radii and spacing, and is a contrast bug
  for colours (see §4).
- **Support:** `light-dark()` is Baseline since May 2024 (Chrome 123, Firefox 120, Safari 17.5).
  weft_ui already needs CSS anchor positioning, which is newer, so this adds no new floor and needs
  no fallback.

The other way, a `prefers-color-scheme: dark` media block plus `:root[data-theme=dark]` and
`[data-theme=light]` blocks, repeats every token three times. It can't be scoped to a subtree
without repeating them again, and it leaves the native controls light unless `color-scheme` is set
anyway.

### 2. Choosing a scheme: `WeftUi.ColorScheme`

A small static module with three classes: `ColorScheme.system` (`color-scheme: light dark`),
`ColorScheme.light` and `ColorScheme.dark`. An app puts one on its outermost element (or any
subtree):

```rescript
<div className={Css.cx([Theme.root, WeftUi.ColorScheme.system])}> ... </div>
```

- **Following the system** needs nothing more, and has no flash: the browser resolves it before the
  first paint.
- **A switch the person sets** (light, dark or system) is the app's. Like the gallery's theme
  switcher, it puts the class on the element at once and keeps the choice in a cookie, so the server
  renders the next page with it. That avoids the flash a client-only choice would give on every
  load. The README shows the pattern. weft_ui doesn't ship the switch itself, since where a choice
  is kept is the app's business.
- **`body`** isn't inside the app's root, so the README tells apps to set the scheme on `:root` (a
  `Css.global` beside their `root` class, as they do with the tokens) when the body's background
  should follow too.

### 3. The dark palette

- **Neutral, like the light one:** zinc greys.
  - `bg` is the darkest colour. `surface` is a step lighter, so a card or dialog stands out from the
    page, which light mode does with a border and a shadow.
  - `surfaceMuted` is lighter again.
- **Tones are lightened** so that text in them, and their `*SoftFg` on their `*Soft`, keep 4.5:1. A
  dark `*Soft` background is a dim tint of the tone.
- **The text on a solid tone** (`accentFg` and the others) may flip to dark where white on the
  lighter tone falls below 4.5:1. The tokens already allow for this, since the text colour on each
  tone is its own token.
- **The non-token colours:**
  - **Shadows:** `rgb(0 0 0 / x)` is kept, with stronger opacities in dark mode (`light-dark()`
    works inside a shadow's colour). Surfaces' lightness does most of the work.
  - **The `Switch` thumb** becomes a token, `controlThumb`: white in both schemes for now, but
    themeable.
  - **The backdrop** stays black, darker in dark mode.

### 4. Contrast, checked

- **A unit test over the token pairs**, in both schemes. It parses each default's `light-dark()`
  pair and computes the WCAG ratio:
  - 4.5:1 for each text colour on `bg`, `surface` and `surfaceMuted`
  - 4.5:1 for each `*Fg` on its tone, and each `*SoftFg` on its `*Soft`
  - 3:1 for `borderStrong` and `focusRing` on `bg` and `surface`

  The v1 README already promises these ratios for light mode; nothing checks them yet.

- **The same check runs on each demo app's palette,** so an app that sets a plain colour for both
  schemes fails the test. Ideally the gallery's palettes would get it too.
- **axe in dark mode:** the gallery's e2e runs axe on every page with the dark scheme in Chromium,
  Firefox and WebKit, and each app's a11y test runs once more in dark, in Chromium.

### 5. The gallery

- **The theme switcher gets a second control:** light, dark or system, kept in a cookie like the
  palette, and combined with it. Each demo app's palette can then be seen in both schemes.
- **The code samples and the frames** need nothing: they're drawn with tokens already.

## Phases

| Phase | What                                                                                                                                                                                                                                                                                                                                   |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | **Spike** (scratchpad only): `light-dark()` through `Css.var` and `weft_css`'s extraction; jsdom's tolerance of it, since the harness's `unstyled` check reads styles; `::backdrop` and native controls under `color-scheme: dark` in the three browsers; how `color-scheme: normal` on an untouched page resolves. Correct this plan. |
| 1     | **weft_ui:** the dark values, `ColorScheme`, `controlThumb` and the non-token colours, the contrast test (finding and fixing any light-mode misses), README and changeset. If the spike finds that weft_css needs a `LightDark(color, color)` constructor for typed colour props, its own commit and changeset.                        |
| 2     | **The gallery:** the scheme control, and axe in dark mode on every page in three browsers. A look at every page in both schemes.                                                                                                                                                                                                       |
| 3     | **The apps:** weft_notes' and weft_shop's palettes as pairs, the shop's own hard-coded colours made into tokens or pairs, both apps following the system (`ColorScheme.system`), the contrast test on their palettes, and their axe tests in dark.                                                                                     |

One PR, a commit per framework change, and a check-in with you between phases, as for v1.

## Decisions

1. **The mechanism.** Recommendation: `light-dark()` with `color-scheme` (§1). It's the least CSS,
   it scopes to subtrees, and the native controls follow. The media query and attribute blocks are
   the alternative.
2. **On by default, or opt-in?** Recommendation: **opt-in** (`ColorScheme.system`). Turning dark
   mode on by default would flip any app that set some tokens as plain colours into a half-dark
   page. Opting in costs one class.
3. **What the demo apps do.** Recommendation: **follow the system**, with no switch of their own.
   The gallery has the full switch (light, dark, system) to show the pattern, and an app switch
   would be the same code again.
4. **Ship a scheme switch in weft_ui?** Recommendation: **not now.** It needs a place to keep the
   choice (a cookie the server reads), which is the app's, and the gallery's is a short example to
   copy. It can be added later as a ready-made entrypoint if apps keep writing the same one.
5. **The dark palette's look.** Recommendation: neutral zinc greys with a lightened blue accent,
   matching the light theme's neutrality. The exact values come out of the contrast test, and will
   be shown in the gallery for review in phase 2.

## Risks

- **A plain colour in an app's palette is a silent bug in dark mode.** For example, the shop's
  `#1d1b19` text on a dark `surface`. The contrast test on each app's palette catches this for the
  demo apps. For other apps, the README says it, and the token docs say which tokens are colours.
- **jsdom may not parse `light-dark()`**, and may drop the declarations, so the harness's styled
  checks could misread. Phase 0 checks this. Most harness tests don't read colours.
- **`::backdrop` inheritance.** Newer engines let the backdrop inherit from its dialog (and so get
  its `color-scheme` and the tokens). Older ones don't, which is why the backdrop stays a fixed
  black rather than a token.
- **Images and gradients.** The shop's product pictures and hero gradients are light pastels that
  will glare on a dark page. Phase 3 gives them dark pairs, and some may stay as they are, the way a
  photo would.
