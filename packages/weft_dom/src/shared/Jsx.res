/***
The JSX module for the DOM: `@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})`.

`Weft.JsxCore` plus host tags taking `DomProps.props`. Any tag name works. Elements are the same
type as every other JSX module's, so components written against `Weft.Jsx` (no host tags) can be
used here. (No `.resi`: this is `JsxCore` plus `Elements`.)
*/

include Weft.JsxCore

module Elements = {
  type props = DomProps.props

  let jsx: (string, props) => element = Weft.JsxCore.hostJsx
  let jsxs: (string, props) => element = Weft.JsxCore.hostJsxs
  let jsxKeyed: (string, props, ~key: string=?, unit) => element = Weft.JsxCore.hostJsxKeyed
  let jsxsKeyed: (string, props, ~key: string=?, unit) => element = Weft.JsxCore.hostJsxsKeyed

  external someElement: element => option<element> = "%identity"
}
