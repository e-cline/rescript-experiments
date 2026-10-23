@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
An entrypoint that renders another (`Counter`) itself, as a client component would: its chunk
imports `Counter`'s.
*/

@weft.component({kind: Entrypoint})
let make = (~title: string) =>
  <section className="outer">
    <h2> {Weft.Jsx.string(title)} </h2>
    <Counter label="inner" />
  </section>
