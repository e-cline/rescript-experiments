@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
Shared components: `@weft.component` with no argument, next to the same component written with
`@jsx.component`. The two should compile to the same thing.
*/

module ViaWeft = {
  @weft.component
  let make = (~name: string, ~children: option<Weft.Element.t>=?) =>
    <section id={name}>
      <h1> {Weft.TestJsx.string(name)} </h1>
      {children->Option.getOr(Weft.TestJsx.null)}
    </section>
}

module ViaJsx = {
  @jsx.component
  let make = (~name: string, ~children: option<Weft.Element.t>=?) =>
    <section id={name}>
      <h1> {Weft.TestJsx.string(name)} </h1>
      {children->Option.getOr(Weft.TestJsx.null)}
    </section>
}
