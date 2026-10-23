@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/***
Entrypoints in modules: `Tabs` (using the shared module and the large one), and `Error`, which
ReScript exports as `$$Error`.
*/

module Tabs = {
  @weft.component({kind: Entrypoint})
  let make = (~count: int) =>
    <div> {WeftDom.Jsx.string(Shared.label("tabs", count) ++ Big.lookup(count))} </div>
}

module Error = {
  @weft.component({kind: Entrypoint})
  let make = (~message: string) => <p> {WeftDom.Jsx.string("error: " ++ message)} </p>
}
