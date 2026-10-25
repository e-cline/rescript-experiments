@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/*** An entrypoint with styles of its own: both directives, the entrypoint's first. */
open WeftCss

let button = Css.class({cursor: Pointer})

@weft.component({kind: Entrypoint})
let make = (~label: string) => <button className=button> {Weft.TestJsx.string(label)} </button>
