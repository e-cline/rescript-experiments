# Plan: UI components for Weft (`weft_ui`)

A package of common, accessible UI components for Weft (layout, text, cards, buttons, form fields,
tables, dialogs, menus, tabs, toasts and more), written in ReScript with
[`weft_css`](../packages/weft_css). Each has default styles, and each can be restyled through theme
tokens, variant props, `className` and state attributes. Then `weft_notes` and `weft_shop` move onto
it, replacing their own markup and styles, and a gallery app shows every component.

```rescript
open WeftUi

<Card.Root>
  <Card.Header>
    <Heading level=#h2> {text("Sign in")} </Heading>
  </Card.Header>
  <Stack gap=#sm>
    <Field.Root invalid={error->Option.isSome}>
      <Field.Label> {text("Your name")} </Field.Label>
      <Input value=name autoComplete="name" onInput />
      <Field.Error> {text(error->Option.getOr(""))} </Field.Error>
    </Field.Root>
    <Button variant=#primary type_="submit" busy> {text("Sign in")} </Button>
  </Stack>
</Card.Root>
```

## Status

Reviewed. The questions are settled (Decisions). Phases 0 to 3 are done, on the branch
`claude/weft-base-ui-components-c99930`. Phase 0's findings and the notes on phases 1 to 3 ("as
built") are after Phases. The design below is already corrected by them. Phase 4 (overlays) is next.

## What was checked before writing this

Against `main` as of PR 15 (`weft_css`):

1. **What the demo apps hand-roll.** Every client and server component in `weft_notes` (8 client
   components, `Pages`) and `weft_shop` (29 client components, `Ui`, `Pages`, `Blocks`). The
   inventory, and which library component replaces each piece, is in §9.
2. **What Weft gives a component library**, and what it doesn't:
   - **Shared components (`@weft.component` with no kind) rendered by the server can't use hooks.**
     `useState`, `useId`, `useContext` and effects throw there; there are no context providers,
     error boundaries or portals in server output; and host elements rendered on the server can't
     have event handlers or refs. A shared component works fully only inside an entrypoint's tree
     (where it's rendered with fibers, on the server for SSR and in the browser). This splits the
     library in two (§2), and is why some components also come as entrypoints (§3).
   - **Entrypoints in a dependency are found.** The plugin's scan (`scan.ts`, `findPackages`) walks
     the app's ReScript dependencies for entrypoint files as well as style files, so a library can
     ship entrypoints.
   - **Entrypoint props must be serializable**, and the PPX rejects labelled arguments written with
     function types. A library entrypoint can't take an `onOpenChange`, so it's uncontrolled.
   - **`WeftDom.DomProps` is a deliberate subset.** It has no `aria-invalid`, `aria-haspopup`,
     `aria-activedescendant`, `aria-disabled`, `aria-orientation`, `aria-valuenow` and the rest; no
     `data-*` but `data-id` and `data-testid`; no `inert`, `open`, `popover`, `popovertarget` or
     `scope`; no pointer, `toggle`, `close` or `cancel` events. `WeftDom.Dom` has no `contains`,
     `showModal`, `relatedTarget` or `getBoundingClientRect`. §7 lists what has to be added.
   - **Portals bubble DOM events through the DOM, not the component tree** (unlike React). Base UI's
     overlays are portal-based. With Weft's portals, a click inside a menu's popup doesn't reach the
     menu's root, so detecting "a click outside" gets awkward. That's one reason this plan uses the
     browser's top layer instead (Decision 2).
   - **ReScript components have no rest props.** A component's props are a record generated from its
     labelled arguments. There's no `{...rest}` that forwards arbitrary attributes to the element
     (§4).
3. **`weft_css`'s rules**:
   - Styles are static, so variants are a class each, picked at render time.
   - The server sends a sheet when a class from it appears in the output. That holds for a
     dependency's style files too: the plugin scans the app's ReScript dependencies.
   - **Every class is in the layer `weft.components`, and rules from different files in one layer
     have no order.** So an app's `className` on a library component would be a coin toss against
     the library's own class (§5).
   - **`Css.var` declares its default on `:root` in `weft.base`.** An app that sets the same
     variable on `:root` is in the same layer at the same specificity, so its override is a coin
     toss too (§5).
4. **The reference libraries.**
   - [Base UI](https://base-ui.com/react/components/fieldset) is unstyled. It has 37 components,
     built from parts (`Dialog.Root`, `Dialog.Trigger`, `Dialog.Popup`, ...). State shows up as
     `data-*` attributes (`data-open`, `data-disabled`, `data-highlighted`). State can be controlled
     or uncontrolled (`open` / `defaultOpen` / `onOpenChange`), and a `render` prop swaps the
     element a part renders.
   - [shadcn/ui](https://ui.shadcn.com/) is styled. It adds Card, Table, Badge, Breadcrumb,
     Skeleton, Sheet, Alert, Spinner and Empty, and "variant recipes" (`buttonVariants()`) that give
     a class string anything can wear.
   - [Astryx](https://astryx.atmeta.com/) is StyleX-based and styled, with themes and dark mode. Its
     site lists few details, so it contributed the "styled by default, themed through tokens" goal
     more than any specific API.
5. **The platform, October 2026.** The browser now does much of what these libraries built in
   JavaScript:
   - `<dialog>.showModal()` gives a modal in the top layer, with the rest of the page inert, focus
     kept in it, and Escape to close.
   - The Popover API (Baseline since 2024) gives a top layer, light dismiss and Escape for menus,
     popovers and toasts.
   - CSS anchor positioning places popups against their triggers, with fallbacks when there's no
     room. It's in Chrome and Edge 125, Safari 26, and
     [Firefox 147 (January 2026)](https://web.dev/blog/web-platform-01-2026), so it's Baseline.
   - `<details name>` gives exclusive accordions.
   - The catch is jsdom, which the tier 2 harness uses: as far as I know it implements neither
     `showModal` nor popovers. Phase 0 checks this.

## Design

### 1. The package

`packages/weft_ui`, `@e-cline/weft_ui`, namespace `WeftUi`:

- **Dependencies:** `weft`, `weft_dom`, `weft_css`, with `ppx_weft` in its `ppx-flags`. Added to the
  root `rescript.json`'s dependencies, as every package is.
- **Not `weft_server`.** The library knows nothing of navigation or RPCs, so it works in a
  client-only app (`weftCss()`) too.
- **One file per component**, so one stylesheet per component. A page loads the sheets of the
  components it renders, and the token sheet they depend on.
- **Components are shared components** (`@weft.component`, no kind). A few also come as ready-made
  entrypoints (§3). Nothing is server-only.

```
packages/weft_ui/src/
  Tokens.res(i)           the theme's CSS variables, and the layer name (§5)
  Layout: Stack, Grid, Container, Separator
  Text: Heading, Text, Link, VisuallyHidden
  Surfaces: Card, Alert, Badge, EmptyState
  Data: Table, List, DescriptionList, Breadcrumbs, Steps
  Status: Spinner, Skeleton
  Actions: Button, IconButton, Toggle, ToggleGroup
  Forms: Field, Fieldset, Form, Input, Textarea, Select, Checkbox, RadioGroup, Switch, NumberField
  Overlays: Dialog, AlertDialog, Drawer, Popover, Menu, Tooltip, Toast
  Disclosure: Tabs, Accordion, Collapsible
  Combobox
  entrypoints/  TabsEntry, DialogEntry, DrawerEntry, PopoverEntry, ToastViewport (§3)
  internal/     DOM bindings, useControllable, roving focus, typeahead, ids
tests/          rescript-vitest + jsdom
```

### Components in v1

45 components, and 5 ready-made entrypoints (§3). **Kind** is from §2: _static_ components can be
rendered by a server component; _interactive_ ones must be inside an entrypoint's tree. **Used by**
is where the demo apps need it (§9); "gallery" means only the gallery app uses it, and it's in v1
because it's a common need, or a sibling of one that's used.

| Component       | Parts                                                                                     | Kind        | Used by                                       |
| --------------- | ----------------------------------------------------------------------------------------- | ----------- | --------------------------------------------- |
| **Layout**      |                                                                                           |             |                                               |
| Stack           | one element; `direction`, `gap`, `align`, `justify`, `wrap`                               | static      | both: headers, forms, toolbars                |
| Grid            | one element; `columns`, or `minItemWidth` for auto-fill; collapses on narrow              | static      | shop: product grids, page columns             |
| Container       | one element; `size` (`#sm` to `#xl`)                                                      | static      | both: the page frame                          |
| Separator       | one element; `orientation`                                                                | static      | both: the hairlines                           |
| **Text**        |                                                                                           |             |                                               |
| Heading         | one element; `level` (`#h1` to `#h6`), `size`                                             | static      | both                                          |
| Text            | one element; `tone`, `size`, `weight`, `italic`, `as_` (`#p`, `#span`, ...)               | static      | both: muted dates, hints, loading text        |
| Link            | one `<a>`; and `Link.className()`                                                         | static      | both, through the apps' navigating `Link`     |
| VisuallyHidden  | one element                                                                               | static      | shop: the currency label                      |
| **Surfaces**    |                                                                                           |             |                                               |
| Card            | `Root`, `Header`, `Title`, `Description`, `Content`, `Footer`                             | static      | shop: product cards, cart summary             |
| Alert           | `Root` (`tone`), `Title`, `Description`, `Action`                                         | static      | both: error box, block errors, offline banner |
| Badge           | one element (`tone`, `variant`); and `Badge.className()`                                  | static      | both: stock, related-note chips               |
| EmptyState      | `Root`, `Title`, `Description`, `Action`                                                  | static      | shop: empty cart, no results, no orders       |
| **Data**        |                                                                                           |             |                                               |
| Table           | `Root`, `Caption`, `Head`, `Body`, `Foot`, `Row`, `HeaderCell`, `Cell`                    | static      | shop: cart lines, orders                      |
| List            | `Root` (`divided`), `Item`                                                                | static      | notes: notes list, comments                   |
| DescriptionList | `Root` (`layout`), `Term`, `Details`                                                      | static      | shop: cart summary                            |
| Breadcrumbs     | `Root`, `Item`, `Current`                                                                 | static      | shop: product and category pages              |
| Steps           | `Root`, `Step` (`#complete`, `#current`, `#upcoming`)                                     | static      | shop: checkout steps, order timeline          |
| **Status**      |                                                                                           |             |                                               |
| Spinner         | one element, with a label for screen readers                                              | static      | both: "Saving…", "Loading…"                   |
| Skeleton        | one element; `lines`, or a size                                                           | static      | shop: placeholders while streaming            |
| **Actions**     |                                                                                           |             |                                               |
| Button          | one `<button>` (`variant`, `size`, `busy`); and `Button.className()`                      | static      | both: everywhere                              |
| IconButton      | one `<button>` with a required `~label`                                                   | static      | shop: ×, ‹ ›, − +                             |
| Toggle          | one `<button aria-pressed>`                                                               | interactive | shop: wishlist heart, gallery thumbnails      |
| ToggleGroup     | `Root` (single or multiple), `Item`                                                       | interactive | shop: product variants                        |
| **Forms**       |                                                                                           |             |                                               |
| Field           | `Root` (`invalid`, `disabled`), `Label`, `Description`, `Error`                           | interactive | both: every labelled control                  |
| Fieldset        | `Root`, `Legend`                                                                          | interactive | shop: checkout steps, facets                  |
| Form            | one `<form>`: `onSubmit` with the default prevented, an error summary                     | interactive | both: every form                              |
| Input           | one `<input>`, wired to its `Field`                                                       | interactive | both                                          |
| Textarea        | one `<textarea>`, wired to its `Field`                                                    | interactive | shop: gift note                               |
| Select          | a native `<select>`, wired to its `Field`; and `Select.Option`                            | interactive | shop: currency, sort, review order, quantity  |
| Checkbox        | one `<input type="checkbox">` with its label; `indeterminate`                             | interactive | shop: facet choices                           |
| RadioGroup      | `Root` (a fieldset, with its `name`), `Radio`                                             | interactive | shop: delivery speed                          |
| Switch          | one `<input type="checkbox" role="switch">` with its label                                | interactive | shop: the "on sale" facet                     |
| NumberField     | `Root` (`min`, `max`, `step`), `Input`, `Decrement`, `Increment`                          | interactive | shop: cart quantities, price range            |
| **Overlays**    |                                                                                           |             |                                               |
| Dialog          | `Root`, `Trigger`, `Popup`, `Title`, `Description`, `Close`                               | interactive | shop: sign in                                 |
| AlertDialog     | as Dialog, plus `Cancel` and `Action`; no light dismiss                                   | interactive | gallery                                       |
| Drawer          | as Dialog, with `side`                                                                    | interactive | shop: the cart drawer                         |
| Popover         | `Root`, `Trigger`, `Popup`, `Title`, `Close`                                              | interactive | gallery                                       |
| Menu            | `Root`, `Trigger`, `Popup`, `Item`, `LinkItem`, `Group`, `GroupLabel`, `Separator`        | interactive | shop: the account menu                        |
| Tooltip         | `Root`, `Trigger`, `Popup`                                                                | interactive | gallery (labels for icon buttons)             |
| Toast           | `createManager`, `add`, `Viewport`, and `Root`, `Title`, `Description`, `Action`, `Close` | interactive | shop: every toast                             |
| **Disclosure**  |                                                                                           |             |                                               |
| Tabs            | `Root` (`orientation`), `List`, `Tab`, `Panel`                                            | interactive | shop: the tabbed blocks                       |
| Accordion       | `Root` (`exclusive`), `Item`, `Trigger`, `Panel`, on `<details>`                          | static      | shop: product Q&A                             |
| Collapsible     | `Root`, `Trigger`, `Panel`, on `<details>`                                                | static      | gallery                                       |
| **Search**      |                                                                                           |             |                                               |
| Combobox        | `Root`, `Input`, `Popup`, `Item`, `Empty`                                                 | interactive | shop: search suggestions                      |

What's not in v1, and might be later, is under "Not in v1", at the end.

### 2. Two kinds of component: static and interactive

Because of the hook rule above (point 2 under "What was checked"), every component is one of two
kinds, and its docs say which:

- **Static (server-safe):** calls no hooks, so a server component can render it directly. Handlers
  are optional props, which work once the component is inside an entrypoint.
  - Stack, Grid, Container, Separator
  - Heading, Text, Link, VisuallyHidden
  - Card, Alert, Badge, EmptyState
  - Table, List, DescriptionList, Breadcrumbs, Steps
  - Spinner, Skeleton
  - Button, IconButton
  - Accordion and Collapsible, which are native `<details>`, so they open and close with no
    JavaScript. They're server-safe when uncontrolled.
- **Interactive (client):** uses state, context, `useId` or effects, so it must be rendered inside
  an entrypoint's tree, as the demo apps' interactive pieces already are.
  - Everything in Forms, and Toggle and ToggleGroup
  - Everything in Overlays
  - Tabs and Combobox
  - Rendered from a server component, these fail at run time with Weft's "hooks don't run on the
    server" error. For the common cases, a server component uses a ready-made entrypoint instead
    (§3).

A follow-up in `weft_server` could make `useId` and `useContext` work in server renders (Not in v1,
at the end). With that, most interactive components could render their initial HTML from a server
component, and fewer ready-made entrypoints would be needed.

### 3. Ready-made entrypoints

For the interactive components a server component most often wants as they are, the library also
ships an entrypoint (`@weft.component({kind: Entrypoint})`), each in a file of its own under
`src/entrypoints/`. Each is a thin wrapper around the compound component:

- **Its props are data:** strings, polymorphic variants, and elements the server rendered.
- **Its state is uncontrolled**, since an entrypoint can't take callbacks.
- **It passes `dataId` and `className` through** to its root.

| Entrypoint      | Props                                                                                                           | Wraps   | Replaces                   |
| --------------- | --------------------------------------------------------------------------------------------------------------- | ------- | -------------------------- |
| `TabsEntry`     | `~labels: array<string>`, `~panels: array<Weft.Element.t>`, `~defaultIndex=?`, `~orientation=?`                 | Tabs    | shop's `Tabs` entrypoint   |
| `DialogEntry`   | `~trigger: Weft.Element.t` (the button's content), `~triggerVariant=?`, `~title`, `~description=?`, `~children` | Dialog  | gallery; e.g. a size guide |
| `DrawerEntry`   | as `DialogEntry`, plus `~side=?`                                                                                | Drawer  | gallery                    |
| `PopoverEntry`  | `~trigger`, `~triggerVariant=?`, `~title=?`, `~children`                                                        | Popover | gallery                    |
| `ToastViewport` | `~placement=?`                                                                                                  | Toast   | shop's `Toaster`           |

`ToastViewport` shows the toasts of a module-level default manager. Any client code calls
`Toast.add(...)`, and a server layout places `<ToastViewport />` once.

Each entrypoint is a chunk of its own. The plugin's scan includes entrypoints nothing renders (a
known, harmless cost), so every app depending on `weft_ui` builds these five chunks, and loads only
the ones its pages render.

Left out on purpose:

- **Menu.** Its common server-side use is a menu of links, but in-place navigation needs
  `WeftServer.Navigation`, which `weft_ui` doesn't depend on.
- **Tooltip.** Its trigger is the element it describes, which would have to be rendered inside the
  entrypoint.

Both are under "Not in v1".

### 4. Component API conventions

- **Parts are nested modules** for compound components: `<Dialog.Root>`, `<Dialog.Trigger>`,
  `<Dialog.Popup>`, `<Dialog.Title>`. The parts share state through a context, as Base UI's do.
  Single-element components are a plain module: `<Button>`, `<Badge>`.
- **Variants are polymorphic variants**, such as `variant=#primary` or `size=#sm`. They need no
  `open`, read well, and are plain strings at run time, so an entrypoint can take them as props from
  the server.
- **Controlled or uncontrolled** state, with Base UI's names: `~open`, `~defaultOpen`,
  `~onOpenChange` (or `value`, `defaultValue`, `onValueChange`). An internal `useControllable` hook
  does this.
- **Common props on every part:** `?id`, `?className` (merged after the defaults), `?style`,
  `?dataId` (so the apps' tests keep finding elements), `?children`, plus the ARIA props that part
  needs (`?ariaLabel`, ...). Because ReScript has no rest props, the escape hatch for anything else
  is `?attrs: WeftDom.DomProps.props`, under the part's element's props (Decision 4). **What the
  part sets wins; what it leaves unset leaves `attrs`'.** As first built (a JSX spread), an absent
  `?style` wrote `undefined` over `attrs.style` (phase 0), which bit twice in phase 3; phase 4's
  first commit merges them in `Host.withAttrs` instead.
- **Recipes:** each styled component also exposes its classes as a function:
  - `Button.className(~variant=#primary, ~size=#sm, ())`
  - `Badge.className(~tone=#muted, ())`
  - `Link.className()`

  A recipe is how something that isn't the component looks like it. The apps' navigating `Link`
  entrypoint can look like a button, and a server component can pass a recipe's class to an
  entrypoint as a string. This is shadcn's `buttonVariants`. It's simpler than Base UI's `render`
  prop, works from server components, and needs nothing from the type system.

- **`render` prop: not in v1.** It could take `~render: WeftDom.DomProps.props => Weft.Element.t`,
  but recipes cover the cases the apps have.
- **State is shown in ARIA attributes where ARIA has one** (`aria-expanded`, `aria-selected`,
  `aria-pressed`, `aria-checked`, `aria-invalid`, `aria-disabled`, `aria-current`). Where it
  doesn't, there's a small fixed set of data attributes: `data-state` (`open`/`closed`),
  `data-orientation`, `data-highlighted`, `data-side` and `data-variant`. Apps style state through
  `selectors: [("&[aria-expanded=\"true\"]", ...)]`, which the shop already does.
- **Labels are required by type where a11y needs one.** `IconButton` takes `~label: string`, not an
  optional `ariaLabel`, and `Dialog.Popup` needs a `Dialog.Title`, or else `~ariaLabel`.

### 5. Styles and customization

There are five ways to change how something looks, from broadest to narrowest:

1. **Tokens**: CSS variables in `Tokens.res`.
   - Colours: `fg`, `fgMuted`, `bg`, `surface`, `border`, `accent`, `accentFg`, `danger`, `success`,
     `warning`, and a soft background for each tone.
   - Radii (`sm`, `md`, `lg`, `full`), a space scale (4px steps), font sizes, a focus ring, a
     shadow, and motion durations.
   - An app sets them once on `:root` (each demo app sets its own palette), or on any element for
     part of the page, with `Css.vars` in a `style` prop.
2. **Variant and size props**: `variant`, `tone`, `size`.
3. **`className`**, which wins over the library's own rules (see below).
4. **State selectors** on ARIA and data attributes (§4).
5. **`style`**, for per-instance variables.

**The default look is neutral**: greys, with a blue accent. Each demo app sets the tokens to its own
palette (the notes' blue and paper, the shop's rust and cream), which also proves the tokens are
enough to restyle the library.

What "`className` wins" requires:

- **The library's classes go in a sublayer, `weft.components.ui`**, through
  `Css.class(~layer=Tokens.layer, ...)`. A layer's own rules beat its sublayers', so an app's class
  (in `weft.components` itself) overrides the library's whatever order the sheets loaded in. This
  needs no change to `weft_css`, if extraction handles a dotted layer name as expected (phase 0).
- **Within the library**, variant classes come after the base class in the same file, so they're in
  a known order. Cross-file composition (Field styling an Input) spreads fragments, never stacks
  classes.
- **Token defaults have zero specificity.** This is a small `weft_css` change: declare `Css.var`
  defaults on `:where(:root)`, not `:root`. An app's `:root { --x: ... }` then wins in any order
  (Decision 3).
- **An app's token values must be in a sheet the page is sent** (phase 0). A sheet goes to a page
  when one of its classes renders there, or when a sheet that does uses its variables. A theme file
  that only sets the library's tokens on `:root`, with no class rendered, would never be sent. So an
  app sets its tokens on a class it puts on its outermost element (`Theme.root`, with
  `vars: [(Tokens.accent, ...)]`), which also scopes them. Top-layer popups stay in their DOM place,
  so they inherit them. The other option is a `:root` global in a file whose classes every page
  renders. The README says this, and the gallery's theme switcher works this way.
- **The library sets no element-level globals** (no `button { ... }` reset). The apps' current
  `button, input` globals go away as the components replace those elements. Body font and background
  stay in the apps' themes, using the library's tokens. A global in the token file would also load
  implicitly with any component, which is surprising.
- **Motion respects `prefers-reduced-motion`**, and focus rings use `:focus-visible`.
- **Layout uses logical properties** (`paddingInline`, `insetInlineEnd`), so right-to-left text
  works. Phase 1 adds these to `weft_css` (§7).
- **Light theme only in v1. Dark mode is for later** (under "Not in v1"). The tokens are named for
  roles (`surface`, `fgMuted`), not colours (`white`, `grey600`), so a dark theme is only a second
  set of values under `prefers-color-scheme: dark` (or a `data-theme` attribute), with no component
  changes. Phase 1's token review checks every token against that rule.

### 6. Accessibility

Every interactive component follows the matching
[ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/patterns/) pattern, with its keyboard
model:

| Component           | Pattern and keyboard                                                                                                 |
| ------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Dialog, AlertDialog | native `<dialog>` with `showModal()`: inert page, focus trapped, Escape closes, focus returns to the trigger         |
| Drawer              | a Dialog whose popup is pinned to one side (`~side`)                                                                 |
| Popover             | the Popover API (`popover="auto"`): light dismiss, Escape; the trigger has `aria-expanded` and `aria-controls`       |
| Menu                | menu button: Enter, Space or ArrowDown opens on the first item; arrows, Home/End, typeahead; Escape and Tab close    |
| Tooltip             | `popover="manual"`, opened on hover and focus after a delay; Escape closes; `aria-describedby`; never the only label |
| Tabs                | roving `tabindex`, arrows (by orientation), Home/End, automatic activation; panels stay mounted (`hidden`)           |
| ToggleGroup         | `role="group"`, `aria-pressed`, roving focus, single or multiple                                                     |
| RadioGroup          | native radios in a `fieldset`, with the browser's arrow keys                                                         |
| Checkbox, Switch    | native `<input type="checkbox">` (Switch has `role="switch"`); `indeterminate` set through a ref                     |
| Select              | native `<select>`, styled (Decision 5)                                                                               |
| NumberField         | `<input inputmode="decimal">` with −/+ buttons; ArrowUp/Down and PageUp/PageDown step; clamped on blur               |
| Combobox            | editable combobox with a listbox popup: `aria-activedescendant`, arrows, Enter picks, Escape clears or closes        |
| Accordion           | `<details>` and `<summary>`; exclusive accordions through `name`                                                     |
| Toast               | an `aria-live` region (`polite`, or `assertive` for errors); pauses on hover and focus; each toast can be dismissed  |
| Field               | label `for`; description and error in `aria-describedby`; `aria-invalid`; the error `role="alert"` once it's shown   |

Popups (Menu, Popover, Tooltip, Combobox's listbox) are placed by CSS anchor positioning, with
`position-try` fallbacks for flipping, and no JavaScript positioning. Each trigger gets a unique
`anchor-name` from `useId` (`--` and the ID, which is a valid dashed ident).

What phase 0 added:

- **Overlays return focus to their trigger themselves.** WebKit doesn't focus a button when it's
  clicked, so a closing `<dialog>` restores focus to `<body>`, not the trigger.
- **The library tracks open state itself**, from `close`, `cancel` and `toggle` events. It never
  asks the DOM with `:modal` or `:popover-open`, which jsdom can't answer.

### 7. Changes needed in the framework

These land in this PR, each in a commit of its own in phase 1.

- **`weft_dom`:**
  - `DomProps` gains the ARIA attributes the patterns need:
    - `aria-invalid`, `aria-required`, `aria-disabled`, `aria-readonly`, `aria-errormessage`
    - `aria-haspopup`, `aria-activedescendant`, `aria-autocomplete`
    - `aria-orientation`, `aria-multiselectable`, `aria-owns`
    - `aria-valuemin`, `aria-valuemax`, `aria-valuenow`, `aria-valuetext`
    - `aria-atomic`, `aria-relevant`, `aria-roledescription`, `aria-level`, `aria-sort`
  - Data attributes: the fixed set in §4.
  - Other attributes: `inert`, `open`, `popover`, `popoverTarget`, `popoverTargetAction`, `scope`,
    `rowSpan`, `headers`, `minLength`, `pattern`, `multiple`, `size`, `form`, `lang`, `dir`.
  - Events: `onPointerDown`, `onPointerEnter`, `onPointerLeave`, `onFocusIn`, `onFocusOut`,
    `onToggle`, `onBeforeToggle`, `onClose`, `onCancel`.
  - Each new prop needs a check that `Html` and `DomHost` write it the same way.
  - `Dom` gains `contains`, `matches`, `closest`, `relatedTarget`, `showModal`, `close`,
    `showPopover`, `hidePopover`, `togglePopover`, `scrollIntoView`, and document listeners. The
    library could keep these bindings internal, but other apps will want them too.
- **`weft_css`:**
  - Variable defaults on `:where(:root)` (Decision 3).
  - Logical properties: `paddingInline`, `paddingBlock`, `marginInline`, `marginBlock`,
    `insetInline`, `insetBlock`, `inlineSize`, `blockSize`, `borderInline*`.
  - Anchor positioning: `anchorName`, `positionAnchor`, `positionArea`, `positionTry`.
  - Also `appearance`, `accentColor`, `textOverflow`, `translate` and `scale`.
  - `::backdrop` and `:popover-open` can be reached through `selectors` already.
- **A jsdom shim, shipped by `weft_ui`, not the harness** (phase 0). jsdom 30 has no `show`,
  `showModal`, `close`, popover methods or `inert`.
  - The harness renders pages in vitest's global jsdom document, so the shim can be a test setup
    file that patches `HTMLDialogElement.prototype` and `HTMLElement.prototype`. It opens and closes
    by attribute, focuses the first focusable element, and fires `close`, `cancel` and `toggle`, and
    handles Escape.
  - `weft_ui`'s own tests and the apps' `setupFiles` both use it, so `weft_vite_plugin` needs no
    change. It's only in tests; real behaviour is checked in Playwright.

### 8. Testing, and the gallery

- **Unit tests** (`rescript-vitest` + jsdom), per component:
  - the ARIA wiring: ids, `aria-*`, roles
  - keyboard models, by dispatching key events
  - controlled and uncontrolled state
  - recipes giving the expected classes
  - static components rendering through `WeftDom.Html` with no hooks, as a server would
- **Styles:** a test that every library class is in `weft.components.ui`, and that an app class
  overrides one. Run once in a browser with the sheets loaded in both orders.
- **The apps' tests stay green.** Tier 2 (the harness) and tier 3 (Playwright) find elements by
  `data-id`, roles and ARIA attributes, so every part passes `dataId` through. Markup changes the
  migration makes on purpose (§9) update their tests in the same commit.
- **Automated a11y checks:** [`@axe-core/playwright`](https://github.com/dequelabs/axe-core-npm), a
  new dev dependency, runs on the gallery's pages and each app's main pages, and on overlays while
  they're open. There's also a manual pass with VoiceOver in Safari over Dialog, Menu, Combobox,
  Tabs and Toast.
- **The gallery app**, `examples/weft_ui_gallery` (`@e-cline/weft_ui_gallery_example`):
  - A `weft()` server app with a page per group (layout, text, surfaces, data, actions, forms,
    overlays, disclosure, search). Every component appears in every variant, tone and size, with a
    short code sample beside it.
  - Static components are rendered straight from server components, interactive ones from the
    gallery's entrypoints, and the ready-made entrypoints as a server component would use them. That
    exercises each component the way §2 and §3 say it can be used.
  - A theme switcher that sets the tokens to each demo app's palette, to show customization, and
    later dark mode.
  - It grows with each phase: a phase's components get their gallery page in the same phase, as
    their visual check.
  - Its e2e suite: axe on every page, keyboard walks through each interactive pattern in §6, and the
    overlays in Chromium, Firefox and WebKit.

### 9. Migrating the demo apps

What each app hand-rolls today, and what replaces it:

| Today                                                                                                          | Becomes                                                                        |
| -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `Theme.res` colours (both apps), `button, input` globals                                                       | the app sets library tokens; the globals are removed                           |
| Notes `Styles.app`, shop `Ui.Styles.app` (max-width, centred)                                                  | `Container size=#md` and `#lg`                                                 |
| Headers, toolbars, forms laid out with ad-hoc flex and grid                                                    | `Stack`, `Grid`                                                                |
| Notes `Theme.secondary`, `Theme.loading`; muted text                                                           | `Text tone=#muted`                                                             |
| Notes `Theme.error`, `ErrorBox`; shop `BlockFrame` error, `OnlineBanner`                                       | `Alert tone=#danger` (with an action slot for Retry) and `Alert tone=#warning` |
| Notes `Theme.list` (comments, notes list)                                                                      | `List.Root divided=true`                                                       |
| Notes related chips, shop stock label                                                                          | `Badge`, or `Badge.className()` on a `Link`                                    |
| Shop product card                                                                                              | `Card`                                                                         |
| Shop "Nothing here yet", "Nothing matches", "No orders yet", the empty cart                                    | `EmptyState`                                                                   |
| Shop `Theme.placeholder` and "Loading…" paragraphs                                                             | `Skeleton`, or `Text tone=#muted` with `Spinner`                               |
| Shop `cta`, `post`, like and wishlist buttons, the steppers' − and +, × dismiss, carousel ‹ and ›              | `Button` variants, `IconButton`, `Toggle` (wishlist, gallery thumbnails)       |
| Shop product variants (`role="group"` with `aria-pressed`)                                                     | `ToggleGroup`                                                                  |
| Every label, input and error triple (checkout, sign-in, newsletter, promo, facets, comment form, title editor) | `Field` with `Input`, `Textarea`, `Select`                                     |
| Checkout and facet fieldsets, delivery radios, facet checkboxes, the "on sale" toggle                          | `Fieldset`, `RadioGroup`, `Checkbox`, `Switch`                                 |
| Range facet "From/To", cart quantity steppers                                                                  | `NumberField`                                                                  |
| Currency, sort and review-order selects, quantity select                                                       | `Select`                                                                       |
| `SignInDialog` (a portal, hand-written Escape and click-outside)                                               | `Dialog` (still the app's, opened from anywhere by `Store`)                    |
| `CartBadge`'s drawer (a portal, no focus handling)                                                             | `Drawer`                                                                       |
| `AccountMenu` ("Hi, name" and Sign out)                                                                        | `Menu` (Account, Sign out)                                                     |
| `Toaster` and `Store.toast`                                                                                    | `ToastViewport` in the shell; `Store.toast` calls `Toast.add`                  |
| `Tabs` entrypoint                                                                                              | `TabsEntry`; the app's file goes                                               |
| `SearchBox` suggestions (a listbox with no keyboard support)                                                   | `Combobox`                                                                     |
| Cart lines (a grid in a `ul`), order list                                                                      | `Table`                                                                        |
| Cart summary `dl`                                                                                              | `DescriptionList`                                                              |
| Product Q&A `dl`                                                                                               | `Accordion`                                                                    |
| Breadcrumbs, checkout steps, order timeline                                                                    | `Breadcrumbs`, `Steps`                                                         |
| `visuallyHidden`                                                                                               | `VisuallyHidden`                                                               |

What stays app code:

- Navigation `Link`, which needs `WeftServer.Navigation`. It wears `Link.className()`, or a button's
  recipe.
- `Price`, `Carousel` (it uses the library's buttons), `Gallery`'s picture gradients, the CMS
  blocks' hero and tiles.
- Page layouts beyond `Stack` and `Grid`.

**Behaviour changes are made where they improve the app**, each in a commit of its own with its test
changes, so any one can be dropped in review:

- Account becomes a menu.
- Cart lines become a table.
- Search gets arrow-key suggestions.
- The drawer traps focus and returns it to the cart button.
- The "on sale" toggle becomes a switch.
- The product Q&A becomes an accordion.

Where a change would only differ, not improve, the app keeps its current behaviour.

## Phases

Each phase ends green and reviewed, as before, with one PR for all of them, the framework changes
included. Each phase's components get their gallery page in the same phase.

| Phase | What                                                                                                                                                                                   |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | Spikes (below), and this plan corrected by them                                                                                                                                        |
| 1     | Framework additions (§7); the package skeleton, `Tokens`, internal helpers; the static components (§2), Button and IconButton included; the gallery app's skeleton and its first pages |
| 2     | Forms: Field, Fieldset, Form, Input, Textarea, Select, Checkbox, RadioGroup, Switch, NumberField; Toggle and ToggleGroup                                                               |
| 3     | **`weft_notes` migrated**: it needs only phases 1 and 2, so the API meets a real app early                                                                                             |
| 4     | Overlays: Dialog, AlertDialog, Drawer, Popover, Menu, Tooltip, Toast; `DialogEntry`, `DrawerEntry`, `PopoverEntry`, `ToastViewport`; the jsdom shim                                    |
| 5     | Tabs, Accordion, Collapsible, Combobox; `TabsEntry`                                                                                                                                    |
| 6     | **`weft_shop` migrated**; axe checks in the gallery's and both apps' e2e                                                                                                               |
| 7     | READMEs (the package's: every component with its kind, parts, props and keyboard), changesets, the gallery's theme switcher and code samples finished                                  |

### Phase 0 spikes

1. **JSX spread onto host elements.** Does `<div {...attrs} className=... />` compile with
   `DomProps.props`, and do explicit props win?
2. **A sublayer from a dependency.** Does `Css.class(~layer="weft.components.ui", ...)` in a library
   package extract and get sent like an app's? Does an app class override it in Chromium, Firefox
   and WebKit, with the sheets loaded in both orders?
3. **`:where(:root)` defaults.** Try them with `weft_shop`'s and `weft_notes`' themes and the tier 3
   flash test.
4. **Native dialog and popover under Weft.**
   - A `<dialog>` that a layout effect opens with `showModal()`, hydrated from server HTML, closed
     by Escape, with its `close` event setting state.
   - A popover anchored by `anchor-name`, with a flip fallback, in all three browsers.
   - What jsdom has, and the shim the harness needs.
5. **`useId` in an entrypoint's SSR** for a compound component whose parts sit at different depths:
   the ids must match in the HTML and after hydration.
6. **An entrypoint from a dependency**, rendered by an app's server component: found by the scan,
   given an id with the library's package name, its chunk and sheet loaded with the row that uses
   it, and hydrated.

### Phase 0: what the spikes found

**The setup.** A throwaway library package (`weft_ui_spike`: tokens, a Button, compound Tabs, a
native Dialog, an anchored Popover, and a `TabsEntry` entrypoint), and an app using it from a server
component and from an entrypoint of its own. They were linked into the workspace for the check, then
removed; their sources are in the session's scratchpad, not committed.

- **Toolchain:** ReScript 12.3.1, ppx_weft, the workspace's Vite+ (1.3.0), and jsdom 30.1.3.
- **Browsers:** Chromium, Firefox and WebKit from Playwright 1.63, driven by a probe script against
  the built app.

**The findings** (the design above is corrected by them):

1. **JSX spread works.** `<button {...attrs} className=... ?dataId />` compiles with
   `DomProps.props`, to a copy of `attrs` with the explicit props assigned after it, so explicit
   props win. The catch is that an absent optional prop is assigned too, as `undefined`, wiping the
   same key in `attrs`. So `attrs` is only for props the part doesn't take (§4).
2. **The sublayer works, with no change to `weft_css`.**
   - `Css.class(~layer="weft.components.ui", ...)` in a dependency extracts to
     `@layer weft.components.ui {...}`, and minifying keeps the layer.
   - The sheet is sent with the rows that use its class, like an app's.
   - With the page's stylesheet links in their order, then reversed, the app's class won both times
     in all three browsers.
3. **Token overrides were a coin toss, and `:where(:root)` fixes them.**
   - Before the change: the app's `:root` value for a library token won with the sheets in one
     order, and lost to the library's default (blue, not green) with them reversed. That happened in
     all three browsers.
   - With `Serialize` writing the defaults on `:where(:root)`, the app's value won in both orders
     everywhere.
   - Nothing else changed:
     - `weft_css`'s tests (30) pass with one expectation updated (`Extract_test`'s pinned CSS).
     - The plugin's tests (233), `weft_shop`'s harness tests (48) and e2e suite (23, the tier 3
       flash test included), and `weft_notes`' (29 and 10) all pass unchanged.
   - The change was reverted after the check; it lands in phase 1.
   - **Also found:** an app's token values reach a page only if their sheet is sent (§5).
4. **The native dialog and popover work under Weft, in all three browsers.**
   - **The dialog:**
     - A `<dialog>`, server-rendered closed and opened by `showModal()` from a layout effect after
       hydration, is modal (`:modal`). It focuses its first focusable element, and the page behind
       it doesn't take clicks.
     - Escape closes it, and its `close` event set the state back, so the trigger opens it again. A
       Close button closes it.
     - Focus returned to the trigger in Chromium and Firefox but not in WebKit, which doesn't focus
       a clicked button. Overlays restore focus themselves (§6).
   - **The popover:**
     - With `popover="auto"` and anchor positioning (`position-anchor`,
       `position-area: bottom span-right`, `position-try-fallbacks: flip-block, flip-inline`), it
       opened 4px below its trigger and left-aligned with it.
     - With the trigger moved to the bottom of the window, it flipped to 4px above it.
     - Escape and a click outside closed it.
     - Since `popover` isn't in `DomProps` yet, the spike set it in a layout effect, so the server's
       HTML showed the popup until hydration. That confirms the `popover` attribute in §7.
   - **jsdom has none of this:** no `show`, `showModal` or `close` on `HTMLDialogElement`, no
     popover methods, no `inert`, and `:popover-open` parses but never matches. Patching the
     prototypes (open by attribute, focus the first focusable element, fire `close`) worked, which
     gives the shim's shape (§7).
5. **`useId` across compound parts matches.** The ID in the Tabs root (used for every tab's and
   panel's `id` and `aria-*`) and one in each tab, deeper down, were the same in the server's HTML
   and after hydration, in all three browsers, with nothing logged.
6. **An entrypoint from a dependency works end to end.**
   - It was found by the scan, with the ID `@e-cline/weft_ui_spike/src/entrypoints/TabsEntry.res#`.
   - Its chunk was preloaded in the head, and its sheets were sent as `C` rows.
   - The server-rendered panels showed it before hydration, and it hydrated and switched tabs in all
     three browsers.

### Phase 1: as built

A commit each:

- **`weft_dom`** (f0ca262): the props, events and bindings in §7, with a test rendering every new
  prop on the server and the client and comparing the DOMs.
  - `open` is a keyword, so the prop is `open_`, as `type_` is.
  - `dataHighlighted` is a boolean attribute; the other data attributes are strings.
- **`weft_css`** (f699843): `:where(:root)`, and the properties in §7. It also gained `captionSide`,
  `resize`, `transformOrigin`, `counterReset` and `counterIncrement`. Steps number themselves with a
  counter of their own, since `counter(list-item)` doesn't count an item that isn't
  `display: list-item`. `ppx_weft`'s tests pinned the old `:root` (2e04fb4).
- **`weft_ui`** (58499f8): `Tokens`, and the static components.
  - **The shared variant types are in `Variants`**, not `Types`: `weft_shop` has a `Types` of its
    own, which `open WeftUi` would shadow. For the same reason (`Link`, later `Tabs`), the README
    suggests `module Ui = WeftUi` over `open WeftUi`.
  - **Reduced motion is in the tokens.** The duration tokens are zero under
    `prefers-reduced-motion: reduce`, and the spinner's turn is slower. That media rule, on
    `:where(:root)` in the tokens' sheet, is the library's only global.
  - **A busy submit button stops its form's submit** with a click handler. So a busy `#submit`
    button can't be rendered by a server component, where host elements can't have handlers. Busy
    buttons are a client thing anyway.
  - **The tests:**
    - Server-safety: every static component is rendered by `weft_server`'s `Render`, which fails on
      any hook (a component with state is the control). `weft_server` is only a dev dependency.
    - Layers: every compiled source file is imported while recording, as the plugin's extraction
      does, and the test checks that no rule is in `weft.components` itself and that the only global
      is the tokens' root. Dropping one class's `~layer` fails it.
    - Behaviour: ARIA and behaviour in jsdom, 20 tests.
- **`weft_ui_gallery`** (b73f764): pages for layout, text, surfaces, data, and actions and status,
  as server components. The sidebar is a navigating entrypoint wearing `Link.className()`, and a
  busy-button demo is an entrypoint.
  - **Its harness test (8)** opens every page: each renders, hydrates as served, and has nothing
    unstyled. It also checks that the sidebar navigates in place and that the demo button goes busy,
    then done.
  - **Checked by eye** in Chromium screenshots. That found two things to fix: row headers in a
    table's body inherited the column headers' bottom alignment and muted colour, and a divided list
    drew a line under its last item.
  - **Code samples** beside the examples are phase 7's.
- The whole workspace's tests pass, and `pnpm check` is clean.

### Phase 2: as built

A commit each:

- **`weft_dom`: `noValidate`** (c9e44ea), so a `Form` shows its page's own errors rather than the
  browser's bubbles.
- **`weft_dom`: controlled radio buttons** (68eade2). Clicking a radio button unchecks the others in
  its group with no event of their own. So a controlled group whose state ignored the click ended
  with nothing checked: only the clicked button's `checked` was put back. Now, after an event, the
  others with its name in its form get theirs back too, as React does. `RadioGroup`'s tests found
  it, and a `weft_dom` test fails without the fix.
- **`weft_css`: the logical corners' radii** (dfebba0), for `NumberField`'s buttons and input joined
  into one control, right in either direction.
- **`weft_ui`: the forms and toggles** (c51041c). The design followed §4 and §6; what it settled:
  - **`Field` takes its label, description and error as props** (`label`, `description`, `error`),
    not as parts. So it knows, as it renders, which of them exist for the control's
    `aria-describedby`, on the server as on the client, with nothing registered after mounting.
  - **An error makes the control invalid.** `error` set means `aria-invalid`, and its region (a
    polite live region, always there and empty without an error) is added to the control's
    `aria-describedby`.
  - **The controls read the field from a context** (`internal/FieldContext`): its `id`, what
    describes it, invalid, required, disabled. A control's own props win over the field's.
  - **`Checkbox`, `Switch` and `RadioGroup` are the platform's inputs.** The checkbox and radios are
    in the accent colour (`accent-color`). The switch is a checkbox with `role="switch"`, its track
    the input itself and its thumb a background that slides. Their `dataId` is the input's.
  - **The control and its label line up.** These controls take the label's font, so they sit centred
    on the first line of their label (inputs default to a smaller font, which put them off by a
    pixel or two: seen in the screenshots).
  - **`NumberField` commits on blur or Enter.** What's typed is a draft until then; a number is kept
    in bounds, and anything else is put back. The −/+ buttons are out of the tab order (the arrow
    keys do the same) and disabled at the ends.
  - **`Fieldset` has no `aria-invalid`**, which isn't allowed on a group. Its error describes it.
    Its items are in a box of their own, so an empty error region adds no gap.
  - **`ToggleGroup` is one Tab stop**: the pressed item, or the one focused last. While nothing's
    pressed or focused, every item is one. The arrow keys move through the enabled items
    (`internal/Roving`, which tabs and menus will share), and Home and End go to the ends.
  - **Controlled or uncontrolled state** comes from `internal/Controllable`.
  - **Tests**: 25 more, in jsdom.
- **`weft_ui_gallery`: the forms page** (6719ef2): a sign-up form that checks itself, every control
  in its states, and its harness test filling the form in after submitting it empty. Checked by eye
  in Chromium. That found the choices' alignment, a gap under a fieldset, and a two-field grid
  leaving a column empty.
- The whole workspace's tests pass. `pnpm check` has only the plugin's three earlier warnings.

### Phase 3: as built

**`weft_notes` on `weft_ui`** (b5e16d6), in one commit.

- **The theme** is the notes' colours as weft_ui's tokens, set on `:root` by the theme file, whose
  `root` class (on the `Container`) brings its sheet to every page.
  - The element rules for buttons, inputs, links and headings are gone.
  - What's left of the notes' own styles: the page's frame (the nav's rule, the comments section's
    rule), the note's body, and the related chips' row.
- **The pages:**
  - The layout is a `Container` and `Stack`s. The note list is a divided `List`, and the comments
    are one too.
  - The related notes are a `List` of links wearing
    `Badge.className(~variant=#outline, ~link=true, ())`.
  - The error box is an `Alert`, and the loading texts are muted, italic `Text`.
  - The navigating `Link` (the app's entrypoint) wears `Link.className()`.
- **The forms:**
  - The comment form and the title editor are `Form`s with `Field`s. The comment's name and text
    have visible labels now, and the hint is the text field's description.
  - A refused comment or title says why on its own field when it's about it (empty, too long), or at
    the form's top for anything else (the note's gone, a request the server couldn't read).
  - The tests find errors as assistive technology does: by the input's `aria-invalid` and the last
    id in its `aria-describedby` (`fieldError`), or by the form's alert (`formError`).
- **The tests**: the harness tests (29) and the browser tests (10) pass. Two of them pinned what
  weft_ui changed: the title's `<h1>` markup, and the comment form's own stylesheet, which is
  weft_ui's `Field` and `Input` sheets now.
- **Checked by eye** in Chromium: the list, a note, and a refused comment. A flex column's
  stretching made the like button full width, so it's in a `div`.
- **What it taught about the library:**
  - **The `attrs` rule bites.** Twice the first draft put `style` in `attrs` (on a `Container` and a
    `Stack`), where the part's own absent `style` wiped it. The compiler can't catch it. Phase 4
    should fix it rather than document it (and did: `Host.withAttrs`): merge only the explicit props
    that are set over `attrs`, in `Host`, and use that for every part's element.
  - **Tokens go on `:root`, in a sheet a class brings.** The first draft set the palette on the
    outermost element's class, which `<body>` can't see, so the page's background and text colour
    were the palette's values written again. Since a sheet is sent with the classes it has, the
    theme file's global can set the tokens on `:root` (winning over weft_ui's `:where(:root)`) as
    long as its `root` class is on the page. That's what the notes do now (a commit of its own), and
    what weft_ui's README and `Tokens` recommend.
- The whole workspace's tests and `pnpm check` pass (with the plugin's three earlier warnings).

## Decisions

Settled in review. The recommendations below were taken, and the questions answered as noted.

1. **Styled components with a customization layer, not headless plus a skin.** Base UI-style parts
   and behaviour, with shadcn-style default styles built in. Every part has default classes,
   overridable through §5. The alternative, headless behaviour hooks (`useDialog`, `useMenu`) plus a
   separate styled layer, doubles the API to maintain for a benefit (fully custom markup) that
   `className`, recipes and `attrs` mostly cover.
2. **The platform over JavaScript re-implementations.**
   - What it means: `<dialog>.showModal()`, the Popover API, CSS anchor positioning, native
     `<select>`, checkboxes and radios, and `<details>`. No portals, focus-trap code or positioning
     library.
   - Why: less code, the browser's own a11y behaviour, and no fight with Weft's DOM-only portal
     events.
   - The cost: jsdom can't run these, so tests need a shim and Playwright. Styling `<select>`'s
     popup and `<details>`' animation is limited.
3. **App tokens win through `Css.var` defaults on `:where(:root)`.** It's one line in `weft_css` and
   changes no app's behaviour (they don't override their own variables). The alternative was
   `Css.var(~layer=...)`, which is more general but adds API.
4. **Explicit common props plus an `attrs` escape hatch**, not every `DomProps` field on every
   component: it keeps the generated prop records small and the docs readable.
5. **Native `<select>` in v1.** The apps' selects are all simple, and the native one has the best
   accessibility on mobile. `appearance: base-select` (customizable select) is still Chromium-only.
6. **Data attributes as a fixed set in `DomProps`** (§4), not a generic `data: dict<string>` prop:
   it's the smallest change to `weft_dom`.
7. **Migrate `weft_notes` mid-way (phase 3)**, so the API is tested on real code before the overlays
   are built.
8. **Some components are also entrypoints** (§3): Tabs, Dialog, Drawer, Popover and the toast
   viewport, uncontrolled, with data props.
9. **The framework changes land in this PR**, a commit each.
10. **v1 is the list in "Components in v1"**, Combobox included, with EmptyState added for the
    shop's empty states. What's left out is listed under "Not in v1".
11. **The name is `weft_ui`**, namespace `WeftUi`.
12. **A neutral default look**, each app setting its own palette. Dark mode later.
13. **`@axe-core/playwright`** is added as a dev dependency.
14. **A gallery app**, `examples/weft_ui_gallery`, built alongside the components (§8).
15. **The migration makes behaviour changes where they improve the app** (§9).

## Risks

- **Interactive components fail on the server only at run time.** This is the hook rule in §2.
  Mitigation: each component's docs say whether it's server-safe, the error names the hook, the
  ready-made entrypoints cover the common cases, and the `useId`/`useContext` on the server
  follow-up removes most of it.
- **Many small stylesheets.** About 45 component files means a page may need ten or more sheets.
  Mitigation: tokens are one sheet, and pages load only what they render. Measure on `weft_shop`;
  `weft_css`'s "group sheets" follow-up is the fix if it matters.
- **Browser-native overlays in tests.** jsdom lacks them, so the jsdom shim could diverge from
  browsers. Mitigation: keep the shim minimal, and put the behaviour that matters in Playwright (the
  gallery's suite covers all three browsers).
- **Anchor positioning is newly Baseline.** Some sub-features (`position-visibility`,
  `anchor-size()`) are still settling across engines. Mitigation: use only the core (`anchor-name`,
  `position-anchor`, `position-area`, `position-try-fallbacks`).
- **Library entrypoints are built into every app.** Five small chunks, whether used or not.
  Mitigation: they're thin; if more are added, the scan could skip entrypoints no server file
  references (an existing follow-up in the server components plan).
- **API churn.** Props will want changing once the apps use them. Mitigation: phase 3 migrates
  `weft_notes` early, and the package is 0.0.x.

## Not in v1

What was decided not to build now, and might be wanted later, most likely first:

1. **Dark mode.** A second set of token values under `prefers-color-scheme: dark`, and a
   `data-theme` attribute to force either. The tokens are named for it (§5), so it needs no
   component changes. It does need a contrast check of every tone in both themes, and the demo apps'
   palettes in dark versions. The gallery's theme switcher is where it would show first.
2. **`useId` and `useContext` in server renders** (`weft_server`). Interactive components could then
   render their initial HTML from server components, which would remove most of the need for
   ready-made entrypoints.
3. **More ready-made entrypoints**: a menu of links (needs in-place navigation, so a small optional
   package that depends on `weft_server`, or navigation that `weft_ui` can reach some other way), a
   tooltip, and a collapsible with remembered state.
4. **A custom listbox `Select`**, or `appearance: base-select` once it's Baseline: for options with
   icons or descriptions, and a styled popup.
5. **Components left out:**
   - Slider, Progress and Meter: no demo app needs them yet.
   - Avatar.
   - Pagination: the shop's "Load more" and the carousel's controls are enough.
   - Toolbar, Menubar, NavigationMenu, ContextMenu.
   - ScrollArea: native scrolling is fine.
   - OTP field.
   - CheckboxGroup: Fieldset and Checkbox cover it.
   - Date picker and calendar.
   - A data table with sorting and selection.
   - Command palette.
   - Preview card, also called hover card.
   - Carousel: the shop's stays app code.
   - Sidebar layout, Kbd, Code.
6. **API extensions, each only if asked for:**
   - a `render` prop to swap a part's element
   - a generic `data-*` prop
   - an `unstyled` mode
   - controlled `Accordion` and `Collapsible`
7. **Grouping the library's sheets**: one stylesheet for the components a page commonly loads
   together, if the number of sheets turns out to matter (`weft_css`'s follow-up 4).
