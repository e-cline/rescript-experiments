# @e-cline/res_fiber_dom

The DOM renderer for [`@e-cline/res_fiber`](../res_fiber): renders `@jsx.component` components into
a browser page. It's a `ResFiber.HostConfig.S` for the DOM, plus a JSX module whose host tags take
DOM props.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/res_fiber @e-cline/res_fiber_dom rescript @rescript/runtime
```

Add both to the `dependencies` in your `rescript.json`. The modules are under the `ResFiberDom`
namespace.

## Using it

```rescript
@@jsxConfig({version: 4, module_: "ResFiberDom.Jsx"})

module Counter = {
  @jsx.component
  let make = () => {
    let (count, setCount) = ResFiber.Hooks.useState(() => 0)
    <button onClick={_ => setCount(c => c + 1)}> {ResFiberDom.Jsx.int(count)} </button>
  }
}

switch ResFiberDom.Dom.document->ResFiberDom.Dom.body->ResFiberDom.Dom.querySelector("#app")
->Nullable.toOption {
| Some(container) => ResFiberDom.Client.createRoot(container)->ResFiberDom.Client.render(<Counter />)
| None => ()
}
```

[`examples/res_fiber_app`](../../examples/res_fiber_app) is a complete app.

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

Not yet: SVG (elements are created without a namespace), delegated events, hydration.

## Testing

`Client.act(f)` calls `f`, then renders every update and runs every effect before returning. The
package's own tests run in jsdom (Vitest's `environment: 'jsdom'`).
