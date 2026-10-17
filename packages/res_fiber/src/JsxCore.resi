/***
Everything ReScript's generic JSX transform needs from a JSX module, except `Elements` (the
lowercase host tags, whose props depend on the renderer).

A file opts in with `@@jsxConfig({version: 4, module_: "<a JSX module>"})` on its first line. In
this workspace the root `rescript.json`'s `jsx` setting belongs to React, so the per-file attribute
is the only way in. The JSX module named there is either `ResFiber.Jsx` (this module alone: no host
tags, so a `<div>` is a compile error and the component works with any renderer) or a renderer's own
module, which is `include ResFiber.JsxCore` plus an `Elements` submodule built on `hostJsx`.

What the transform emits, and so what these functions receive:

- `<Child a=1 />` calls `jsx(Child.make, {a: 1})`; with two or more children, `jsxs`, whose
  `children` prop is a plain JS array.
- `<Child key="k" />` calls `jsxKeyed(Child.make, props, ~key="k", ())`: the key is never in props.
- `<> ... </>` calls `jsxs(jsxFragment, {children: [...]})`.
- `<div ...>` calls `Elements.jsx("div", props)`.
*/

type element = Element.t
type component<'props> = 'props => element
type componentLike<'props, 'return> = 'props => 'return

external component: componentLike<'props, element> => component<'props> = "%identity"

/** An element for `component` with `props`. */
let jsx: (component<'props>, 'props) => element

/** The same as `jsx`; the transform calls this one when there are several children. */
let jsxs: (component<'props>, 'props) => element

/** `jsx`, with a key. */
let jsxKeyed: (component<'props>, 'props, ~key: string=?, unit) => element

/** `jsxs`, with a key. */
let jsxsKeyed: (component<'props>, 'props, ~key: string=?, unit) => element

/** A list of elements, as one element. Give each a `key` when the list can change. */
external array: array<element> => element = "%identity"

/** Renders nothing. */
let null: element

/** Text. */
external string: string => element = "%identity"

/** An `int`, as text. */
external int: int => element = "%identity"

/** A `float`, as text (as JavaScript's `String` would write it). */
external float: float => element = "%identity"

type fragmentProps = {children?: element}

/** What `<> ... </>` is a `jsx` call on. Calling it directly throws. */
let jsxFragment: component<fragmentProps>

/**
`<Fragment key> ... </Fragment>`: a fragment with a key, for lists of fragments (`<> ... </>` can't
take one). The same element as `<> ... </>` otherwise.
*/
module Fragment: {
  type props<'children> = {children?: 'children}
  let make: component<props<element>>
}

external someElement: element => option<element> = "%identity"

/** A host element (`<tag ...>`): what a renderer's `Elements.jsx` is. */
let hostJsx: (string, 'props) => element

/** `hostJsx`, with a key: what a renderer's `Elements.jsxKeyed` is. */
let hostJsxKeyed: (string, 'props, ~key: string=?, unit) => element
