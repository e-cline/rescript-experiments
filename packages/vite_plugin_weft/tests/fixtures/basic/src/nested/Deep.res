@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** An entrypoint in a subdirectory. */

@weft.component({kind: Entrypoint})
let make = (~depth: int) => <p> {Weft.Jsx.string(`deep ${Int.toString(depth)}`)} </p>
