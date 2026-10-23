# @e-cline/weft_dom

The DOM renderer for [`@e-cline/weft`](../weft): renders `@jsx.component` components into a browser
page. It's a `Weft.HostConfig.S` for the DOM, plus a JSX module whose host tags take DOM props. On
the server, `Html` renders the same trees to HTML, streamed, for the client to hydrate.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/weft @e-cline/weft_dom rescript @rescript/runtime
```

Add both to the `dependencies` in your `rescript.json`. The modules are under the `WeftDom`
namespace.

## Using it

```rescript
@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

module Counter = {
  @jsx.component
  let make = () => {
    let (count, setCount) = Weft.Hooks.useState(() => 0)
    <button onClick={_ => setCount(c => c + 1)}> {WeftDom.Jsx.int(count)} </button>
  }
}

switch WeftDom.Dom.document->WeftDom.Dom.body->WeftDom.Dom.querySelector("#app")
->Nullable.toOption {
| Some(container) => WeftDom.Client.createRoot(container)->WeftDom.Client.render(<Counter />)
| None => ()
}
```

[`examples/weft_app`](../../examples/weft_app) is a complete app.

- **`Jsx`**: the JSX module (`@@jsxConfig` names it). Host tags take `DomProps.props`.
- **`Client`**: `createRoot`, `render`, `unmount`, `flushSync`, and `act` for tests.
- **`Portal`**: `<Portal container> ... </Portal>` renders its children into another element. DOM
  events there bubble through the DOM (to `container`'s ancestors), not through the component tree
  as in React.
- **`Dom`**: the small set of DOM bindings the renderer and components need (elements, events,
  `Event.targetValue`, ...).

## Props

`DomProps.props` is one record for every tag, a subset of the DOM to grow as needed:

- `value` and `checked` are set as properties, so inputs are controlled: after an event, a value the
  component didn't change is put back.
- `style` is a `dict<string>` of CSS properties: `dict{"background-color": "red"}` (kebab-case goes
  through `style.setProperty`; camelCase is assigned). Only changed keys are touched.
- `on*` props are event listeners: `onClick` is `click`, `onDoubleClick` is `dblclick`, the rest are
  lowercased. Unlike React, `onChange` is the DOM's `change` event; `onInput` fires on every
  keystroke.
- Everything else is an attribute: `className` is `class`, `htmlFor` is `for`, `type_` is `type`,
  `ariaLabel` is `aria-label`, and `true`/`false` add or remove a boolean attribute.
- `ref` receives the element.

## Behaviour

- **Updates in event handlers render before the event returns**, as in React, so an input never
  shows a value its state doesn't have. Other updates are batched into a microtask.
- **Focus survives moves**: reordering a list doesn't blur the focused element.
- **Listeners are attached once per element and event**; swapping a handler (a new closure every
  render) is a table write, not a remove and add.
- `createRoot` empties its container.

Not yet: SVG (elements are created without a namespace), delegated events.

## Where it runs

The sources are in `src/client/`, `src/server/` and `src/shared/` by where they run. `Html` starts
with the `'use weft server'` directive, so the Vite plugin refuses it to an app's client build.

| Module     | Where   | What it is                                                                |
| ---------- | ------- | ------------------------------------------------------------------------- |
| `Client`   | browser | Roots: `createRoot`, `hydrateRoot`, `render`, `flushSync`, `act`.         |
| `DomHost`  | browser | The reconciler's host for the DOM (internal to `Client`).                 |
| `DomProps` | both    | The props host elements take, and how each is applied.                    |
| `Dom`      | both    | DOM bindings (only touching the DOM when called).                         |
| `Jsx`      | both    | The JSX module for `@@jsxConfig`.                                         |
| `Portal`   | both    | `Portal.make(container, children)`: made anywhere, rendered in a browser. |
| `Html`     | server  | The HTML renderer: a tree to HTML, streamed (`render`, `renderToString`). |

## Testing

`Client.act(f)` calls `f`, then renders every update and runs every effect before returning. The
package's own tests run in jsdom (Vitest's `environment: 'jsdom'`).

## HTML on the server

`Html.render(element)` renders the tree as the client would render it: host elements and their props
by `DomProps`' rules (the same ones `DomHost` follows, so the server writes what the client would
set), text escaped (with `<!-- -->` between two texts in a row, which the parser would merge),
components called through `Weft.ServerRender.renderComponent` (their hooks giving initial state),
providers' values reaching them. `shell` is everything outside pending `Suspense` boundaries; `rest`
streams each boundary's content once it's ready, in a `<template>` an inline script swaps in over
the fallback. `renderToString` waits for everything instead.

A boundary's content is tried at once, and written in place if it's ready. If something in it
suspends, its fallback is written, with markers the client's hydration reads, and the content is
rendered again (with everything that suspended in that try waited for together) until it's ready. An
error under a boundary fails it (`onError` gives the digest); outside every boundary, it fails the
shell. A development build warns about nesting the HTML parser would repair.

The package's tests check, besides each rule, that the HTML parses (in jsdom) into exactly the DOM a
client render of the same tree makes, over random trees, and run the swap runtime against the
segments.

## Hydrating

`Client.hydrateRoot(container, element)` renders `element` over the HTML `Html` wrote into
`container`, adopting its nodes: each element's handlers are attached and its props stored, and
nothing that matches is created. What the user typed into an input, or ticked, before then is kept.
A `Suspense` boundary still pending when hydration reaches it stays as the server's HTML until the
page's runtime swaps its content in (it calls the marker's `$weftRetry`), then hydrates. Where the
HTML and `element` disagree, the nearest boundary (or the root) is rendered on the client, a text
that differs is patched, and attributes that differ are warned about (in development) and left.

`Hooks.useId` gives the same IDs in the HTML as once hydrated: both sides number the tree's levels
the same way (`Html` walks the levels the reconciler makes fibers for). They start with a prefix,
`"w"` unless `Html.render(~idPrefix)` and `Client.hydrateRoot(~idPrefix)` say otherwise, which two
roots on one page need to.

**Events from before hydration** are replayed. `Html.eventRuntime`, in the page's head (`WeftServer`
writes it), records the clicks, submits, inputs and changes on elements under the root that haven't
hydrated yet (not a link's click, which the browser follows; a submit's default is prevented, so the
page stays; only the last input and change on each element). After each commit, the ones whose
elements have hydrated are replayed, in order, through the elements' own listeners (so a checkbox
isn't toggled twice); one whose element hasn't hydrated yet holds back those after it, and one whose
element is gone is dropped.

The tests hydrate the renderer's own HTML in jsdom: the same node objects before and after, handlers
working, typed values kept, boundaries hydrating when swapped in (or already swapped in), failed
boundaries rendered on the client, mismatches recovered from, and events from before replayed
(`Replay_test.res`); and a fuzz test streams random trees' HTML in pieces, hydrates at a random
point, and checks the DOM ends up as a client render's, made only of elements the HTML put there.

## Error codes

Production builds throw `WeftDom error <code>` instead of these messages:

| Code | Development message                                                          |
| ---: | ---------------------------------------------------------------------------- |
|    1 | A host element's tag isn't a tag name.                                       |
|    2 | A prop's attribute name isn't one.                                           |
|    3 | A void element (`<br>`, `<input>`, …) was given children.                    |
|    4 | A `<script>` or `<style>` was given children (their content isn't HTML).     |
|    5 | The HTML suspended 100 times in a row (a new promise every call?).           |
|    6 | An internal element (`Offscreen`) reached the HTML renderer (a bug in Weft). |

Codes don't change once published: a new error gets the next number.
