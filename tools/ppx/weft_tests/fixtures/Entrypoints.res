@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
Entrypoints, at every depth: each is marked with an id naming this file and the modules leading to
it, and the file starts with the `'use weft entrypoint'` directive.
*/

/** A file-level entrypoint is this file's own `make`. */
@weft.component({kind: Entrypoint})
let make = (~count: int) => <output> {Weft.TestJsx.int(count)} </output>

module Nested = {
  @weft.component({kind: Entrypoint})
  let make = (~label: string) => <button> {Weft.TestJsx.string(label)} </button>
}

module Outer = {
  module Inner = {
    @weft.component({kind: Entrypoint})
    let make = (~label: string, ~pressed: option<bool>=?) =>
      <button title={pressed->Option.getOr(false) ? "pressed" : "not pressed"}>
        {Weft.TestJsx.string(label)}
      </button>
  }
}

/**
A module named after a JavaScript global: ReScript exports it under another name (`$$Error`), which
the client has to allow for when it looks up the id's module path.
*/
module Error = {
  @weft.component({kind: Entrypoint})
  let make = (~message: string) => <p className="alert"> {Weft.TestJsx.string(message)} </p>
}

/** A shared component in an entrypoint's file: not marked. */
module Shared = {
  @weft.component
  let make = (~text: string) => <i> {Weft.TestJsx.string(text)} </i>
}
