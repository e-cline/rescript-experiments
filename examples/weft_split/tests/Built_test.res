/***
The same pages through the harness, from the build: the worker runs the built server, and the page
is the built client's own (its bootstrap, chunks and copy of Weft). A build-mode file opens one
page, so this is one walk through the app.
*/

open Vitest
open SplitSupport

type build
@module("./BuildSupport.mjs") external build: string => promise<build> = "build"
@module("./BuildSupport.mjs") external remove: build => unit = "remove"
@get external outDir: build => string = "outDir"

let built = ref(None)
let app = ref(None)
beforeAllAsync(~timeout=60_000, async () => {
  let output = await build("harness")
  built := Some(output)
  app := Some(await WeftTesting.start(~root=packageRoot, ~mode=Build, ~buildDir=outDir(output)))
})
afterAllAsync(async () => {
  await app.contents->Option.getOrThrow->WeftTesting.close
  built.contents->Option.forEach(remove)
})

describe("from the build", () => {
  testAsync("the home page renders, its entrypoints work, and a link navigates", async t => {
    let page = app.contents->Option.getOrThrow->WeftTesting.open_(~container=rootElement(), "/")
    await page->WeftTesting.waitFor(() => homeShows(page))
    page->WeftTesting.click(".counter")
    await page->WeftTesting.waitFor(() => text(page, ".counter") == "clicks: 1")
    page->WeftTesting.click("#other-link")
    await page->WeftTesting.waitFor(() => otherShows(page, ~clicks=1))
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/", "/other"])
  })
})
