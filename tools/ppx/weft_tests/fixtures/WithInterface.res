@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

@weft.component({kind: Entrypoint})
let make = (~greeting: string, ~name: string) =>
  <p> {WeftCore.TestJsx.string(`${greeting}, ${name}!`)} </p>
