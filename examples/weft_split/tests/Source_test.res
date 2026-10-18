/***
The app's pages through the plugin's harness, from the sources: the server in a worker, the pages
in jsdom, each entrypoint loaded when a page first needs it.
*/

open Vitest
open SplitSupport

let app = ref(None)
beforeAllAsync(~timeout=60_000, async () => app := Some(await WeftTesting.start(~root=packageRoot)))
afterAllAsync(async () => await app.contents->Option.getOrThrow->WeftTesting.close)
let app = () => app.contents->Option.getOrThrow

let file = name => `@e-cline/weft_split_example/src/${name}.res`

describe("from the sources", () => {
  testAsync("the home page renders every entrypoint, loading all but the chart's file", async t => {
    let page = app()->WeftTesting.open_(~container=rootElement(), "/")
    await page->WeftTesting.waitFor(() => homeShows(page))
    t
    ->expect(page->WeftTesting.loads->Array.toSorted(String.compare))
    ->Expect.toEqual(["Counter", "Fancy", "Link", "Outer", "Plain", "Widgets"]->Array.map(file))
  })

  testAsync(
    "an entrypoint is interactive, and a link navigates in place, loading the chart then",
    async t => {
      let page = app()->WeftTesting.open_(~container=rootElement(), "/")
      await page->WeftTesting.waitFor(() => homeShows(page))
      page->WeftTesting.click(".counter")
      await page->WeftTesting.waitFor(() => text(page, ".counter") == "clicks: 1")
      page->WeftTesting.click("#other-link")
      await page->WeftTesting.waitFor(() => otherShows(page, ~clicks=1))
      t->expect(page->WeftTesting.loads->Array.includes(file("Chart")))->Expect.toBe(true)
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/", "/other"])
    },
  )
})
