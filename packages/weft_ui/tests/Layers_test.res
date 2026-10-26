/***
weft_ui's stylesheets, extracted as the Vite plugin does: every class and animation in the layer
`weft.components.ui` (so an app's classes win over them), and no rules for elements, the tokens'
`:where(:root)` the only global.
*/
open Vitest

/** Imports every compiled source file, so their style calls register. */
let importAll: unit => promise<unit> = %raw(`async () => {
  for (const load of Object.values(import.meta.glob("../src/**/*.res.js"))) await load();
}`)

describe("the stylesheets", () => {
  testAsync("put every rule of a component in weft.components.ui", async t => {
    WeftCss.Extract.start()
    await importAll()
    let sheets = WeftCss.Extract.finish()
    t->expect(sheets->Array.length > 15)->Expect.toBe(true)
    sheets->Array.forEach(
      ({id, css}) => {
        // Only the layer order statement names `weft.components` on its own.
        let blocks = css->String.split("@layer weft.components {")->Array.length - 1
        t->expect((id, blocks))->Expect.toEqual((id, 0))
        // A global is only ever the tokens' root.
        let base = css->String.split("@layer weft.base {")->Array.slice(~start=1)
        base->Array.forEach(
          block =>
            t
            ->expect((id, block->String.trimStart->String.startsWith(":where(:root)")))
            ->Expect.toEqual((id, true)),
        )
      },
    )
  })
})
