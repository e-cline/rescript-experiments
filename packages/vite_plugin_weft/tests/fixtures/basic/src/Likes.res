@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** A file-level entrypoint, using the shared module. */

@weft.component({kind: Entrypoint})
let make = (~count: int) => <span> {Weft.Jsx.string(Shared.label("likes", count))} </span>
