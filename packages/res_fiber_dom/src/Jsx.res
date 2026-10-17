/***
The JSX module for the DOM: `@@jsxConfig({version: 4, module_: "ResFiberDom.Jsx"})`.

`ResFiber.JsxCore` plus host tags taking `DomProps.props`. Any tag name works. Elements are the same
type as every other JSX module's, so components written against `ResFiber.Jsx` (no host tags) can be
used here. (No `.resi`: this is `JsxCore` plus `Elements`.)
*/

include ResFiber.JsxCore

module Elements = {
  type props = DomProps.props

  let jsx: (string, props) => element = ResFiber.JsxCore.hostJsx
  let jsxs: (string, props) => element = ResFiber.JsxCore.hostJsx
  let jsxKeyed: (string, props, ~key: string=?, unit) => element = ResFiber.JsxCore.hostJsxKeyed
  let jsxsKeyed: (string, props, ~key: string=?, unit) => element = ResFiber.JsxCore.hostJsxKeyed

  external someElement: element => option<element> = "%identity"
}
