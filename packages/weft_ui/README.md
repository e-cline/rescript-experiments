# @e-cline/weft_ui

Accessible, styled UI components for [Weft](../weft): layout, text, cards, tables, buttons, forms,
toggles, dialogs, drawers, popovers, menus, tooltips, toasts, tabs, accordions and a combobox (the
[plan](../../docs/weft_ui_plan.md) has the design). They're styled with [`weft_css`](../weft_css),
so a page is sent only the stylesheets of the components it renders, and each can be restyled
through theme tokens, variant props, `className` and state attributes.

```rescript
module Ui = WeftUi

<Ui.Card.Root as_=#article>
  <Ui.Card.Header>
    <Ui.Card.Title> {text("Wool scarf")} </Ui.Card.Title>
    <Ui.Card.Description> {text("Merino, hand-dyed")} </Ui.Card.Description>
  </Ui.Card.Header>
  <Ui.Stack direction=#row justify=#between align=#center>
    <Ui.Badge tone=#success> {text("In stock")} </Ui.Badge>
    <Ui.Button variant=#primary onClick=add> {text("Add to cart")} </Ui.Button>
  </Ui.Stack>
</Ui.Card.Root>
```

Its modules have plain names (`Link`, `Table`, ...), which an app may have too, so an alias
(`module Ui = WeftUi`) reads better than `open WeftUi`.

## Installing

Needs ReScript 12, `weft`, `weft_dom` and `weft_css`, and [`ppx_weft`](../../tools/ppx/weft): add
`@e-cline/weft_ui` to your `rescript.json`'s `dependencies`, and `"@e-cline/ppx_weft/ppx"` to its
`ppx-flags`. With [`weft_vite_plugin`](../../tools/weft_vite_plugin), its styles are extracted and
sent like your own.

## Static and interactive components

- **Static** components call no hooks, so a server component can render them directly: Stack, Grid,
  Container, Separator, Heading, Text, Link, VisuallyHidden, Card, Alert, Badge, EmptyState, Table,
  List, DescriptionList, Breadcrumbs, Steps, Spinner, Skeleton, Button and IconButton. Event
  handlers (`onClick`) are optional, and work once they're inside an entrypoint.
- **Interactive** components keep state, or read a context, so they render inside an entrypoint's
  tree: Field, Fieldset, Form, Input, Textarea, Select, Checkbox, RadioGroup, Switch, NumberField,
  Toggle, ToggleGroup, Dialog, AlertDialog, Drawer, Popover, Menu, Tooltip, Toast, Tabs and
  Combobox. Their state is controlled (`value` and `onValueChange`, `open_` and `onOpenChange`, ...)
  or, without it, their own (from `defaultValue`, `defaultOpen`).
- **Ready-made entrypoints**, for a server component to render as they are, with data props and
  state of their own: `TabsEntry`, `DialogEntry`, `DrawerEntry`, `PopoverEntry` and `ToastViewport`
  (render it once; client code calls `Toast.add`, and tests `Toast.clear` between them).

Each module's doc comment says which it is.

## Customizing

From broadest to narrowest:

1. **Tokens** (`WeftUi.Tokens`): CSS variables for colours, radii, space, text sizes, shadows and
   durations, named for what they're for. Set them on `:root` in a style file with a class your
   outermost element wears (a sheet is sent to a page with the classes it has), so the page's `body`
   sees them too:

   ```rescript
   Css.global(~selector=":root", {vars: [(WeftUi.Tokens.accent, "#9a4b22")]})
   let root = Css.class({display: Block}) // on the page's outermost element
   ```

   The defaults are on `:where(:root)`, so yours win, whichever sheet loads first. For part of a
   page, set them on a class of that part instead.

2. **Variants**: `variant`, `tone`, `size` and the like, as polymorphic variants (`#primary`).
3. **`className`**, added after the component's own classes. weft_ui's rules are in the cascade
   layer `weft.components.ui`, under your classes' `weft.components`, so yours win.
4. **State**, in ARIA attributes (`aria-expanded`, `aria-current`, ...) or `data-state`,
   `data-variant` and the like, for `selectors` rules of your own.
5. **`style`**, for per-instance variables (`Css.vars`).

Every styled component also has its classes as a function (a recipe), for something else to look
like it: `Button.className(~variant=#primary, ())` on an app's navigating link,
`Badge.className(~link=true, ())` on a chip.

Each part takes `id`, `className`, `style`, `dataId` and the ARIA props it needs. For anything else,
`attrs` (a `WeftDom.DomProps.props`) goes under its element's props: what the part sets itself wins,
and what it leaves unset (its own `style`, say, when you don't give one) leaves `attrs`'.

## Accessibility

Each component follows the matching
[ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/patterns/) pattern, and builds on the
platform's own elements where there is one (`<dialog>`, the Popover API, `<details>`, native
inputs).

- `IconButton` requires its `label`.
- A busy `Button` stays focusable.
- A `List` without markers keeps its list role.
- A `Table` that scrolls is a labelled, focusable region.
- `Steps` and `Breadcrumbs` mark the current item.
- `Spinner` and `Skeleton` say what's loading, or stay out of the way.

## Testing with jsdom

jsdom has neither `<dialog>`'s `showModal` and `close` nor the Popover API. Call
`WeftUi.Testing.installJsdomShims()` once, before rendering (at the top of a test file, or in the
module a suite's pages share), for weft_ui's overlays to open, close and move the focus as they do
in a browser. It doesn't lay anything out, or make anything inert: those are for browser tests.

## Tokens

All in `WeftUi.Tokens`, each a `Css.var` (`Tokens.value(var)` gives `var(--...)` for a string
property):

- **Surfaces and text:** `bg`, `surface`, `surfaceMuted`, `fg`, `fgMuted`, `border`, `borderStrong`,
  `focusRing`.
- **Tones**, each with its hover or text-on-it colour and a soft background with its text:
  - `accent`, `accentHover`, `accentFg`, `accentSoft`, `accentSoftFg`
  - `danger`, `dangerHover`, `dangerFg`, `dangerSoft`, `dangerSoftFg`
  - `success`, `successFg`, `successSoft`, `successSoftFg`
  - `warning`, `warningFg`, `warningSoft`, `warningSoftFg`
  - `neutralSoft`, `neutralSoftFg`
- **Radii:** `radiusSm`, `radiusMd`, `radiusLg`, `radiusFull`.
- **Space:** `spaceXs`, `spaceSm`, `spaceMd`, `spaceLg`, `spaceXl`, `spaceXxl`.
- **Text sizes:** `textXs` ... `textXxxl`.
- **Control heights:** `controlSm`, `controlMd`, `controlLg`.
- **Container widths:** `containerSm`, `containerMd`, `containerLg`, `containerXl`.
- **Shadows and motion:** `shadowSm`, `shadowMd`, `shadowLg`, `durationFast`, `durationMedium`,
  `durationSpin`.

## Components

Every part also takes `id`, `className`, `style`, `dataId` and `attrs` (above), and most take
`children`. Defaults are in brackets. The shared variants are in `WeftUi.Variants`:

- `space` is `#none | #xs | #sm | #md | #lg | #xl | #xxl`
- `size` is `#sm | #md | #lg`
- `tone` is `#neutral | #accent | #success | #warning | #danger`
- `level` is `#h1` ... `#h6`
- `align` is `#start | #center | #end | #stretch | #baseline`
- `orientation` is `#horizontal | #vertical`

A button's `variant` (`Button.variant`) is
`#primary | #secondary | #outline | #ghost | #danger | #link`. A popup's `side` is
`#top | #bottom | #start | #end`, and its `align` is `#start | #center | #end`.

### Layout

| Component | Kind   | Props                                                                                                                                                                    |
| --------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Stack     | static | `as_`, `direction` (`#column`, or `#row`), `gap` (`#md`), `align`, `justify` (`#start \| #center \| #end \| #between`), `wrap`, `ariaLabel`. Recipe: `Stack.className`   |
| Grid      | static | `as_`, `columns` (equal columns), `minItemWidth` (as many as fit), or `template`; `gap` (`#md`), `stackBelow` (`#sm \| #md \| #never`: one column below it), `ariaLabel` |
| Container | static | `as_` (`#div \| #main \| #section \| #header \| #footer`), `size` (`#sm` ... `#xl`, `#full`; `#lg`)                                                                      |
| Separator | static | `orientation` (`#horizontal`), `decorative` (hidden from assistive technology)                                                                                           |

### Text

| Component      | Kind   | Props                                                                                                                                                                                                                                                                                    |
| -------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Heading        | static | `level` (`#h2`), `size` (`#xs` ... `#xxl`; the level's own). Recipe: `Heading.className`                                                                                                                                                                                                 |
| Text           | static | `as_` (`#p`, or `#span`, `#div`, `#small`, `#strong`, `#em`, `#label`), `tone` (`#default \| #muted \| #accent \| #success \| #warning \| #danger`), `size` (`#xs` ... `#lg`), `weight`, `italic`, `numeric` (tabular figures), `truncate`, `role`, `ariaLive`. Recipe: `Text.className` |
| Link           | static | `href`, `tone` (`#accent \| #inherit \| #muted`), `underline` (`#always \| #hover \| #none`), `external_` (a new tab, and says so), `onClick`, `ariaCurrent`. Recipe: `Link.className`                                                                                                   |
| VisuallyHidden | static | `as_` (`#span \| #div`), `focusable` (shown while focused: a skip link)                                                                                                                                                                                                                  |

### Surfaces and status

| Component  | Kind   | Parts and props                                                                                                                                                                                                                    |
| ---------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Card       | static | `Root` (`as_`: `#div \| #article \| #section \| #li \| #aside`; `variant`: `#outline \| #elevated \| #ghost`; `padding`: `#none` ... `#lg`; `interactive`), `Header`, `Title` (`level`, `#h3`), `Description`, `Content`, `Footer` |
| Alert      | static | `Root` (`tone`: `#neutral \| #info \| #success \| #warning \| #danger`, `#info`; `role`: `#alert`, the default for danger and warning, `#status` or `#none`), `Title`, `Description`, `Action`                                     |
| Badge      | static | `tone` (`#neutral`), `variant` (`#soft \| #solid \| #outline`), `size` (`#sm \| #md`), `shape` (`#pill`), `ariaLabel`. Recipe: `Badge.className(~link=true, ())` for a chip                                                        |
| EmptyState | static | `Root` (`bordered`), `Title` (`level`), `Description`, `Action`                                                                                                                                                                    |
| Spinner    | static | `size`, `label` (`"Loading"`), `announce` (`true`: a `status`; `false`: only a picture, inside something busy)                                                                                                                     |
| Skeleton   | static | `shape` (`#text \| #rect \| #circle`), `lines` (`1`), `width`, `height`. It's hidden from assistive technology: mark what's loading busy                                                                                           |

### Data

| Component       | Kind   | Parts and props                                                                                                                                                                                                                                                                                                                   |
| --------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Table           | static | `Root` (`density`: `#comfortable \| #compact`; `striped`; `scrollLabel`, which makes its scrolling box a labelled, focusable region), `Caption` (`hidden`), `Head`, `Body`, `Foot`, `Row` (`selected`), `HeaderCell` (`scope`: `#col \| #row`; `align`; `numeric`; `colSpan`; `ariaSort`), `Cell` (`align`, `numeric`, `colSpan`) |
| List            | static | `Root` (`as_`: `#ul \| #ol`; `divided`; `gap` (`#none`); `markers`, off by default, keeping its list role), `Item`                                                                                                                                                                                                                |
| DescriptionList | static | `Root` (`layout`: `#grid \| #stacked`; `detailsAlign`: `#start \| #end`), `Term`, `Details`                                                                                                                                                                                                                                       |
| Breadcrumbs     | static | `Root` (`label`, `"Breadcrumbs"`), `Item` (put your link in it), `Current` (`aria-current="page"`)                                                                                                                                                                                                                                |
| Steps           | static | `Root` (`orientation`, `ariaLabel`), `Step` (`status`: `#complete \| #current \| #upcoming`; the current one is `aria-current="step"`)                                                                                                                                                                                            |

### Actions

| Component   | Kind        | Props                                                                                                                                                                                                                                                                       |
| ----------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Button      | static      | `variant` (`#secondary`), `size`, `shape` (`#rounded \| #pill`), `fullWidth`, `type_` (`#button \| #submit \| #reset`), `busy` (a spinner; `aria-disabled`, so it stays focusable), `disabled`, `onClick`, `name`, `value`, `title`, ARIA props. Recipe: `Button.className` |
| IconButton  | static      | `label` (required: its name), `variant` (`#ghost`), `size`, `shape`, `type_`, `busy`, `disabled`, `onClick`, `title`, ARIA props. Recipe: `IconButton.className`                                                                                                            |
| Toggle      | interactive | `pressed` or `defaultPressed`, `onPressedChange`, `label` (an icon toggle, named by it), `variant`, `size`, `disabled`. Its name stays the same; `aria-pressed` says whether it's on                                                                                        |
| ToggleGroup | interactive | `Root` (`label`, required; `type_`: `#single \| #multiple`; `value` or `defaultValue`, arrays; `onValueChange`; `orientation`; `variant`; `size`; `disabled`), `Item` (`value`, `label`, `disabled`)                                                                        |

**ToggleGroup's keyboard:** it's one Tab stop (the pressed item, or the last focused). The arrow
keys along its orientation move between items, Home and End go to the ends, and Space or Enter
presses one. A `#single` group's pressed item stays pressed when pressed again.

### Forms

The controls take their label, description and error from the `Field` around them.

| Component   | Kind        | Parts and props                                                                                                                                                                                                                                                                                                                                                                |
| ----------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Form        | interactive | `onSubmit` (the browser's own validation is off), `busy` (`aria-busy`, and a submit does nothing), `error` (an alert at the top), `ariaLabel`                                                                                                                                                                                                                                  |
| Field       | interactive | `label` (required), `hideLabel`, `description`, `error` (in a polite region, always there), `required`, `disabled`; one control as `children`, which gets its `id`, `aria-describedby` and `aria-invalid`                                                                                                                                                                      |
| Fieldset    | interactive | `legend` (required), `hideLegend`, `description`, `error`, `disabled` (all of it), `gap` (`#sm \| #md`)                                                                                                                                                                                                                                                                        |
| Input       | interactive | `type_` (`#text \| #email \| #password \| #search \| #tel \| #url \| #number`), `size`, `value`, `onInput`, `onChange`, `onBlur`, `onFocus`, `onKeyDown`, `name`, `placeholder`, `autoComplete`, `inputMode`, `min`/`max`/`step`, `minLength`/`maxLength`, `pattern`, `readOnly`, `autoFocus`; `invalid`/`required`/`disabled` override the field's. Recipe: `Input.className` |
| Textarea    | interactive | `rows` (`3`), and `Input`'s text props                                                                                                                                                                                                                                                                                                                                         |
| Select      | interactive | The browser's `<select>`: `size`, `value`, `onChange`, `onBlur`, `name`, `autoComplete`, `invalid`/`required`/`disabled`; `Select.Option` (`value`, `disabled`)                                                                                                                                                                                                                |
| Checkbox    | interactive | `checked` (or its own), `onCheckedChange`, `onChange`, `indeterminate`, `description`, `name`, `value`, `required`, `disabled`; its label is `children`                                                                                                                                                                                                                        |
| Switch      | interactive | As `Checkbox`, without `indeterminate` or `required`: `role="switch"`, for a setting that applies at once                                                                                                                                                                                                                                                                      |
| RadioGroup  | interactive | `Root` (`legend`, required; `hideLegend`; `value` or `defaultValue`; `onValueChange`; `name`; `orientation` (`#vertical`); `description`; `error`; `disabled`), `Radio` (`value`, `description`, `disabled`). Native radios: the arrow keys move and choose                                                                                                                    |
| NumberField | interactive | `Root` (`value` or `defaultValue`, floats; `onValueChange`; `min`; `max`; `step` (`1.`); `size`; `disabled`), `Input` (`name`, `ariaLabel`), `Decrement` and `Increment` (`label`)                                                                                                                                                                                             |

**NumberField's keyboard:** what's typed is committed on blur or Enter, then kept within `min` and
`max` (or put back, if it isn't a number). ArrowUp and ArrowDown step, PageUp and PageDown step by
ten, and Home and End go to `min` and `max`. The buttons are out of the tab order.

### Overlays

Each is in the top layer: `Dialog`, `AlertDialog` and `Drawer` with `<dialog>`'s `showModal()`;
`Popover`, `Menu` and `Tooltip` with the Popover API, placed against their trigger with CSS anchor
positioning (and flipped when there's no room). A `Root`'s `open_` and `onOpenChange` control it;
without `open_`, it keeps its own (from `defaultOpen`). A `Trigger` takes a `Button`'s `variant` and
`size`, and `label` for an icon trigger.

| Component   | Kind        | Parts and props                                                                                                                                                                                                                                               |
| ----------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dialog      | interactive | `Root`, `Trigger`, `Popup` (`size`: `#sm \| #md \| #lg`; `dismissible`, `true`: a click on the backdrop closes it; `ariaLabel`), `Title` (`level`, `#h2`; it names the dialog), `Description`, `Footer`, `Close` (`variant`, `label`, `onClick`, `autoFocus`) |
| AlertDialog | interactive | `Dialog`'s parts, with `Popup` not dismissible (`#sm`), `Cancel` (focused as it opens) and `Action` (`variant`, `#primary`; `onClick`, then it closes)                                                                                                        |
| Drawer      | interactive | `Dialog`'s parts, with `Popup`'s `side` (`#start \| #end`, `#end`): pinned to that side, its full height                                                                                                                                                      |
| Popover     | interactive | `Root` (`side`, `#bottom`; `align`, `#start`), `Trigger`, `Popup` (`ariaLabel`), `Title`, `Close`. A non-modal dialog                                                                                                                                         |
| Menu        | interactive | `Root` (`side`, `align`), `Trigger`, `Popup`, `Item` (`onSelect`, `disabled`, `tone`: `#default \| #danger`), `LinkItem` (`href`, `onClick`), `Separator`, `Group` (`label`)                                                                                  |
| Tooltip     | interactive | `Root` (`content`, required; `side`, `#top`; `delay`, `500` ms), `Trigger` (`label`, `variant`, `size`, `onClick`, `disabled`)                                                                                                                                |
| Toast       | interactive | `Toast.Viewport` (`placement`: `#bottom \| #top`; `label`, `"Notifications"`; `manager`), rendered once. `Toast.add(~title, ~description=?, ~tone=?, ~duration=?, ~action=?, ())` returns its id; `Toast.dismiss(id)`; `Toast.clear()`                        |

**The keyboard and the focus:**

- **Dialogs** (and drawers): the focus goes to the first focusable element in the popup (an alert
  dialog's `Cancel`, or one with `autoFocus`), and stays in it. Escape closes it, and the focus goes
  back to the trigger.
- **Popover**: the trigger opens it (the platform's `popovertarget`, so it works before hydrating),
  and the focus goes into it. Escape or a click outside closes it, and the focus goes back.
- **Menu**:
  - Enter, Space or ArrowDown on the trigger opens it on its first item; ArrowUp opens it on its
    last.
  - In it, ArrowDown and ArrowUp move (wrapping, past disabled items), Home and End go to the ends,
    and a letter goes to the next item starting with it.
  - Enter or Space chooses, and closes it.
  - Escape or a click outside closes it, and the focus goes back to the trigger; Tab closes it and
    moves on.
- **Tooltip**: shown on hover (after `delay`) or focus, hidden on Escape, leaving or blur. It names
  an icon trigger with its `label`, and otherwise describes the trigger (`aria-describedby`).
- **Toast**: each closes after `duration` ms (`0`: only when dismissed). Nothing closes while the
  pointer or the focus is in the viewport. A `#danger` toast is an alert; others are polite.

### Disclosure

| Component   | Kind        | Parts and props                                                                                                                                                                                                                                            |
| ----------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Collapsible | static      | `Root` (`defaultOpen`, `name`, `onToggle`), `Trigger`, `Panel`. The browser's `<details>` and `<summary>`: it works with no JavaScript, and find-in-page opens it                                                                                          |
| Accordion   | static      | `Root` (`ariaLabel`), `Item` (`name`: the same on every item makes them exclusive; `defaultOpen`), `Trigger`, `Panel`                                                                                                                                      |
| Tabs        | interactive | `Root` (`value` or `defaultValue`; `onValueChange`; `orientation`; `variant`: `#underline \| #pills`; `activation`: `#automatic \| #manual`), `List` (`label`), `Tab` (`value`, `disabled`), `Panel` (`value`; `keepMounted`, `true`: hidden, not removed) |

**Tabs' keyboard:** the tab list is one Tab stop (the selected tab). The arrow keys along its
orientation move between tabs (past disabled ones) and select them, or, with `#manual`, only move,
and Enter or Space selects. Home and End go to the ends. Tab goes on to the panel. Give `Root` a
`defaultValue`: without one, it selects the first tab once it's in the page, so the server's HTML
shows no panel.

### Search

| Component | Kind        | Parts and props                                                                                                                                                                                                                                               |
| --------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Combobox  | interactive | `Root` (`onSelect`, with the chosen item's `value`), `Input` (`value`, `onInput`, `onKeyDown`, `onBlur`, `type_`, `size`, `name`, `placeholder`), `Popup` (render it only while there's something to show), `Item` (`value`, `onSelect`, `disabled`), `Empty` |

**Combobox's keyboard:** typing opens the popup with nothing highlighted. ArrowDown and ArrowUp
highlight the next and previous item (wrapping), with the focus kept in the input and the item its
`aria-activedescendant`. Enter chooses the highlighted item (the item's `onSelect`, then the root's)
and closes the popup; with nothing highlighted, it submits the form. Escape, Tab or leaving closes
it. The text and the items are the app's.

### Ready-made entrypoints

In `WeftUi` like the rest (their files are in `src/entrypoints`), for a server component to render
with data props:

| Entrypoint    | Props                                                                                                                                                                                         |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| TabsEntry     | `labels`, `panels` (server-rendered, in the same order), `label`, `defaultIndex` (`0`), `orientation`, `variant`. Its parts' `data-id`s are `dataId` with `-tab-<n>` or `-panel-<n>` after it |
| DialogEntry   | `trigger` (the trigger's content), `triggerVariant`, `title`, `description`, `closeLabel` (`"Close"`), `size`; its `children` are the dialog's                                                |
| DrawerEntry   | As `DialogEntry`, with `side` in place of `size`                                                                                                                                              |
| PopoverEntry  | `trigger`, `triggerVariant`, `title`, `side`, `align`; its `children` are the popover's                                                                                                       |
| ToastViewport | `placement`, `label`: render it once in the layout, and call `Toast.add` from client code                                                                                                     |
