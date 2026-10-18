@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
Shared components: `@weft.component` with no argument, next to the same component written with
`@jsx.component`. The two should compile to the same thing.
*/

module ViaWeft = {
  @weft.component
  let make = (~name: string, ~children: option<WeftCore.Element.t>=?) =>
    <section id={name}>
      <h1> {WeftCore.TestJsx.string(name)} </h1>
      {children->Option.getOr(WeftCore.TestJsx.null)}
    </section>
}

module ViaJsx = {
  @jsx.component
  let make = (~name: string, ~children: option<WeftCore.Element.t>=?) =>
    <section id={name}>
      <h1> {WeftCore.TestJsx.string(name)} </h1>
      {children->Option.getOr(WeftCore.TestJsx.null)}
    </section>
}
