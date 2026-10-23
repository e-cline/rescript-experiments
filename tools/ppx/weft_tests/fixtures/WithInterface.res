@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

@weft.component({kind: Entrypoint})
let make = (~greeting: string, ~name: string) =>
  <p> {Weft.TestJsx.string(`${greeting}, ${name}!`)} </p>
