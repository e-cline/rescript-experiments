/***
The renderer-agnostic JSX module: `@@jsxConfig({version: 4, module_: "Fiber.Jsx"})`.

It has no `Elements` submodule, so a lowercase tag (`<div>`) in a file using it is a compile error.
Components written against it only compose other components, and work under any renderer. See
`JsxCore` for the rest. (No `.resi`: this is exactly `JsxCore`.)
*/

include JsxCore
