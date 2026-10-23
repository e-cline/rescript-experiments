@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/*** A file-level entrypoint, using the shared module. */

@weft.component({kind: Entrypoint})
let make = (~count: int) => <span> {WeftDom.Jsx.string(Shared.label("likes", count))} </span>
