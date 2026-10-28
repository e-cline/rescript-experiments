/***
An entrypoint that renders another (`Counter`) itself, as a client component would: its chunk
imports `Counter`'s.
*/

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (~title: string) =>
  <section className="outer">
    <h2> {Jsx.string(title)} </h2>
    <Counter label="inner" />
  </section>
