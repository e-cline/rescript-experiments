/***
The gallery through the plugin's harness, from the sources: the server in a worker, the pages in
jsdom. Every page renders its components on the server, hydrates over that HTML, and shows nothing
before its stylesheet has loaded.
*/

open Vitest
open GallerySupport

let app = ref(None)
beforeAllAsync(~timeout=60_000, async () => app := Some(await WeftTesting.start(~root=packageRoot)))
afterAllAsync(async () => await app.contents->Option.getOrThrow->WeftTesting.close)
let app = () => app.contents->Option.getOrThrow

let pages = [
  ("/", "weft_ui"),
  ("/layout", "Layout"),
  ("/text", "Text"),
  ("/surfaces", "Surfaces"),
  ("/data", "Data"),
  ("/actions", "Actions and status"),
]

describe("the gallery", () => {
  pages->Array.forEach(((path, title)) =>
    testAsync(
      `${path} renders, hydrates as served, and is styled`,
      async t => {
        let page = app()->WeftTesting.open_(~container=rootElement(), path)
        await page->WeftTesting.waitFor(() => text(page, "[data-id=page-title]") == title)
        t->expect(await hydratedAsServed(page))->Expect.toBe(true)
        t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
      },
    )
  )

  testAsync("the sidebar marks the page shown, and navigates in place", async t => {
    let page = app()->WeftTesting.open_(~container=rootElement(), "/layout")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=page-title]") == "Layout")
    await page->WeftTesting.hydrated
    t->expect(text(page, "nav [aria-current=page]"))->Expect.toBe("Layout")
    page->WeftTesting.click("[data-id=nav-data]")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=page-title]") == "Data")
    t->expect(text(page, "nav [aria-current=page]"))->Expect.toBe("Data")
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/layout", "/data"])
    t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
  })

  testAsync("a button is busy while it's saving, then says it's done", async t => {
    let page = app()->WeftTesting.open_(~container=rootElement(), "/actions")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=save-demo]") == "Save")
    await page->WeftTesting.hydrated
    page->WeftTesting.click("[data-id=save-demo]")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=save-demo]") == "Saving…")
    t
    ->expect(
      page
      ->WeftTesting.query("[data-id=save-demo]")
      ->Option.flatMap(
        button => WeftDom.Dom.getAttribute(button, "aria-disabled")->Nullable.toOption,
      ),
    )
    ->Expect.toEqual(Some("true"))
    await page->WeftTesting.waitFor(() => text(page, "[data-id=save-demo-status]") == "Saved")
  })
})
