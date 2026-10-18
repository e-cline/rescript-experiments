/***
The JSX module for the DOM: `@@jsxConfig({version: 4, module_: "FiberDom.Jsx"})`.

`Fiber.JsxCore` plus host tags taking `DomProps.props`. Any tag name works. Elements are the same
type as every other JSX module's, so components written against `Fiber.Jsx` (no host tags) can be
used here. (No `.resi`: this is `JsxCore` plus `Elements`.)
*/

include Fiber.JsxCore

module Elements = {
  type props = DomProps.props

  let jsx: (string, props) => element = Fiber.JsxCore.hostJsx
  let jsxs: (string, props) => element = Fiber.JsxCore.hostJsxs
  let jsxKeyed: (string, props, ~key: string=?, unit) => element = Fiber.JsxCore.hostJsxKeyed
  let jsxsKeyed: (string, props, ~key: string=?, unit) => element = Fiber.JsxCore.hostJsxsKeyed

  external someElement: element => option<element> = "%identity"
}
