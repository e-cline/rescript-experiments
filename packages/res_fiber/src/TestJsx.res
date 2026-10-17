/***
The JSX module for `TestRenderer`: `@@jsxConfig({version: 4, module_: "ResFiber.TestJsx"})`.

`JsxCore`, plus host tags whose props are a small fixed set: enough to tell nodes apart (`id`), show
changes (`className`, `title`, `value`, `checked`), and drive interactions (`onClick`, `onInput`)
from a test. Any tag name works. (No `.resi`: this is `JsxCore` plus `Elements`.)
*/

include JsxCore

module Elements = {
  type props = {
    id?: string,
    className?: string,
    title?: string,
    value?: string,
    checked?: bool,
    onClick?: unit => unit,
    onInput?: string => unit,
    children?: element,
  }

  let jsx: (string, props) => element = JsxCore.hostJsx
  let jsxs: (string, props) => element = JsxCore.hostJsx
  let jsxKeyed: (string, props, ~key: string=?, unit) => element = JsxCore.hostJsxKeyed
  let jsxsKeyed: (string, props, ~key: string=?, unit) => element = JsxCore.hostJsxKeyed

  external someElement: element => option<element> = "%identity"
}
