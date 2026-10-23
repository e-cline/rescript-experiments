/***
The JSX module for the DOM: `@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})`.

`WeftCore.JsxCore` plus host tags taking `DomProps.props`. Any tag name works. Elements are the same
type as every other JSX module's, so components written against `WeftCore.Jsx` (no host tags) can be
used here. (No `.resi`: this is `JsxCore` plus `Elements`.)
*/

include WeftCore.JsxCore

module Elements = {
  type props = DomProps.props

  let jsx: (string, props) => element = WeftCore.JsxCore.hostJsx
  let jsxs: (string, props) => element = WeftCore.JsxCore.hostJsxs
  let jsxKeyed: (string, props, ~key: string=?, unit) => element = WeftCore.JsxCore.hostJsxKeyed
  let jsxsKeyed: (string, props, ~key: string=?, unit) => element = WeftCore.JsxCore.hostJsxsKeyed

  external someElement: element => option<element> = "%identity"
}
