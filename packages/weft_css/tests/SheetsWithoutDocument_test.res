/*** Stylesheets without a document (on the server): every one is loaded already. */

open Vitest

describe("Sheets, without a document", () => {
  testAsync("has nothing to load, or wait for", async t => {
    t->expect(WeftCss.Sheets.isLoaded("/a.css"))->Expect.toBe(true)
    await WeftCss.Sheets.load("/a.css")
    t->expect(%raw(`globalThis.__weftCss`))->Expect.toBe(%raw(`undefined`))
  })
})
