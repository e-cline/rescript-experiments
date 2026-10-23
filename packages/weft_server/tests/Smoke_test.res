@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

open Vitest
open Support

describe("a round trip", () => {
  testAsync("renders host elements, text and entrypoints as rendering directly does", async t => {
    let tree =
      <section id="page">
        <h1> {text("Title")} </h1>
        <Wrap id="body">
          <Counter label="a" />
          {text("tail")}
        </Wrap>
      </section>
    t->expect(await renderRoundTrip(tree))->Expect.toBe(renderDirectly(tree))
  })
})
