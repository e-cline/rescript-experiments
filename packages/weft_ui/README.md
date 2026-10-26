# @e-cline/weft_ui

Accessible, styled UI components for [Weft](../weft): layout, text, cards, tables, buttons, forms,
toggles, dialogs, drawers, popovers, menus, tooltips and toasts, and (as the
[plan](../../docs/weft_ui_plan.md)'s phases land) tabs, an accordion and a combobox. They're styled
with [`weft_css`](../weft_css), so a page is sent only the stylesheets of the components it renders,
and each can be restyled through theme tokens, variant props, `className` and state attributes.

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
  Toggle, ToggleGroup, Dialog, AlertDialog, Drawer, Popover, Menu, Tooltip and Toast (and, in later
  phases, tabs and the combobox). Their state is controlled (`value` and `onValueChange`, `open_`
  and `onOpenChange`, ...) or, without it, their own (from `defaultValue`, `defaultOpen`).
- **Ready-made entrypoints**, for a server component to render as they are, with data props and
  state of their own: `DialogEntry`, `DrawerEntry`, `PopoverEntry` and `ToastViewport` (render it
  once; client code calls `Toast.add`).

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
