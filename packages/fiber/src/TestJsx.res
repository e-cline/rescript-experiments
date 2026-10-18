/***
The JSX module for `TestRenderer`: `@@jsxConfig({version: 4, module_: "Fiber.TestJsx"})`.

`JsxCore`, plus host tags whose props are a small fixed set: enough to tell nodes apart (`id`), show
changes (`className`, `title`, `value`, `checked`), drive interactions (`onClick`, `onInput`) from a
test, and receive the node (`ref`). Any tag name works. (No `.resi`: this is `JsxCore` plus
`Elements`.)
*/

include JsxCore

/** A node the test renderer created: what a `ref` receives. See `TestRenderer`. */
type node

module Elements = {
  type props = {
    id?: string,
    className?: string,
    title?: string,
    value?: string,
    checked?: bool,
    onClick?: unit => unit,
    onInput?: string => unit,
    ref?: Ref.t<Nullable.t<node>>,
    children?: element,
  }

  let jsx: (string, props) => element = JsxCore.hostJsx
  let jsxs: (string, props) => element = JsxCore.hostJsxs
  let jsxKeyed: (string, props, ~key: string=?, unit) => element = JsxCore.hostJsxKeyed
  let jsxsKeyed: (string, props, ~key: string=?, unit) => element = JsxCore.hostJsxsKeyed

  external someElement: element => option<element> = "%identity"
}
