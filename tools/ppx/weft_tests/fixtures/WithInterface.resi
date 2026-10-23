@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
A component with an interface: `@weft.component` on the declaration becomes `@jsx.component` there
too, so the declared type matches the implementation's.
*/

@weft.component({kind: Entrypoint})
let make: (~greeting: string, ~name: string) => WeftCore.Element.t
