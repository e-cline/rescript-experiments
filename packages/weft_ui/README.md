# @e-cline/weft_ui

Accessible, styled UI components for [Weft](../weft): layout, text, cards, tables, buttons, and (as
the [plan](../../docs/weft_ui_plan.md)'s phases land) forms, dialogs, menus, tabs, toasts and a
combobox. They're styled with [`weft_css`](../weft_css), so a page is sent only the stylesheets of
the components it renders, and each can be restyled through theme tokens, variant props, `className`
and state attributes.

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
- **Interactive** components (forms, overlays, tabs, the combobox; later phases) keep state, so they
  render inside an entrypoint's tree. A few also come as ready-made entrypoints, for a server
  component to use as they are.

Each module's doc comment says which it is.

## Customizing

From broadest to narrowest:

1. **Tokens** (`WeftUi.Tokens`): CSS variables for colours, radii, space, text sizes, shadows and
   durations, named for what they're for. Set them on a class on your outermost element, which
   brings their stylesheet to every page that renders it:

   ```rescript
   let root = Css.class({vars: [(WeftUi.Tokens.accent, "#9a4b22"), (WeftUi.Tokens.radiusMd, "4px")]})
   ```

   The defaults are on `:where(:root)`, so a value set anywhere wins, whichever sheet loads first.

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
`attrs` (a `WeftDom.DomProps.props`) is spread onto its element first. It's only for props the part
doesn't take itself: those are written after it, even when absent.

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
