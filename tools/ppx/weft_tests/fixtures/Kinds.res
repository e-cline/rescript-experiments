@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
Every kind of component. Until phase 2 of the server components plan, the PPX compiles each of them
as a shared component, so these render like any other.
*/

module Server = {
  @weft.component({kind: Server})
  let make = (~title: string) => <h2> {WeftCore.TestJsx.string(title)} </h2>
}

/** A file-level entrypoint is this file's own `make`. */
@weft.component({kind: Entrypoint})
let make = (~count: int) => <output> {WeftCore.TestJsx.int(count)} </output>

module Nested = {
  @weft.component({kind: Entrypoint})
  let make = (~label: string) => <button> {WeftCore.TestJsx.string(label)} </button>
}

/**
A module named after a JavaScript global: ReScript exports it under another name (`$$Error`), which
the entrypoint ids of phase 2 have to account for.
*/
module Error = {
  @weft.component({kind: Entrypoint})
  let make = (~message: string) => <p className="alert"> {WeftCore.TestJsx.string(message)} </p>
}
