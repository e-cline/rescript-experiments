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
  ("/forms", "Forms"),
  ("/overlays", "Overlays"),
  ("/disclosure", "Disclosure"),
  ("/search", "Search"),
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

  testAsync(
    "the sign-up form shows each field's error, then signs up once they're fixed",
    async t => {
      let page = app()->WeftTesting.open_(~container=rootElement(), "/forms")
      await page->WeftTesting.waitFor(() => page->WeftTesting.has("[data-id=signup]"))
      await page->WeftTesting.hydrated
      page->WeftTesting.click("[data-id=signup-submit]")
      await page->WeftTesting.waitFor(() => page->WeftTesting.has("[data-id=signup] [role=alert]"))
      let invalid =
        page
        ->WeftTesting.query("[data-id=signup-email]")
        ->Option.flatMap(
          input => WeftDom.Dom.getAttribute(input, "aria-invalid")->Nullable.toOption,
        )
      t->expect(invalid)->Expect.toEqual(Some("true"))
      t->expect(page->WeftTesting.html->String.includes("Enter your name."))->Expect.toBe(true)
      page->WeftTesting.input("[data-id=signup-name]", "Ada")
      page->WeftTesting.input("[data-id=signup-email]", "ada@example.com")
      page->WeftTesting.click("[data-id=signup-terms]")
      page->WeftTesting.click("[data-id=signup-submit]")
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=signup-done]")->String.includes("Welcome, Ada"),
      )
    },
  )

  testAsync("a toast added on the overlays page shows in the frame's viewport", async t => {
    let page = app()->WeftTesting.open_(~container=rootElement(), "/overlays")
    await page->WeftTesting.waitFor(() => page->WeftTesting.has("[data-id=toast-neutral]"))
    await page->WeftTesting.hydrated
    page->WeftTesting.click("[data-id=toast-neutral]")
    await page->WeftTesting.waitFor(
      () => text(page, "[data-id=toasts] li")->String.includes("Link copied"),
    )
    t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
  })

  testAsync("the menu opens on its first item, and a choice closes it", async t => {
    let page = app()->WeftTesting.open_(~container=rootElement(), "/overlays")
    await page->WeftTesting.waitFor(() => page->WeftTesting.has("[data-id=menu-open]"))
    await page->WeftTesting.hydrated
    page->WeftTesting.click("[data-id=menu-open]")
    let attribute = (selector, name) =>
      page
      ->WeftTesting.query(selector)
      ->Option.flatMap(element => WeftDom.Dom.getAttribute(element, name)->Nullable.toOption)
    await page->WeftTesting.waitFor(
      () => attribute("[data-id=menu-open]", "aria-expanded") == Some("true"),
    )
    page->WeftTesting.click("[data-id=menu-sign-out]")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=menu-last]") == "Chose: Sign out")
    t->expect(attribute("[data-id=menu-open]", "aria-expanded"))->Expect.toEqual(Some("false"))
  })

  testAsync(
    "the server's tabs switch once hydrated, and the combobox chooses with the keyboard",
    async t => {
      let page = app()->WeftTesting.open_(~container=rootElement(), "/disclosure")
      await page->WeftTesting.waitFor(() => page->WeftTesting.has("[data-id=product-tabs-tab-2]"))
      await page->WeftTesting.hydrated
      page->WeftTesting.click("[data-id=product-tabs-tab-2]")
      let hidden = selector =>
        page
        ->WeftTesting.query(selector)
        ->Option.map(
          panel => WeftDom.Dom.getAttribute(panel, "hidden")->Nullable.toOption->Option.isSome,
        )
      await page->WeftTesting.waitFor(() => hidden("[data-id=product-tabs-panel-2]") == Some(false))
      t->expect(hidden("[data-id=product-tabs-panel-0]"))->Expect.toEqual(Some(true))

      let search = app()->WeftTesting.open_(~container=rootElement(), "/search")
      await search->WeftTesting.waitFor(() => search->WeftTesting.has("[data-id=fruit]"))
      await search->WeftTesting.hydrated
      search->WeftTesting.input("[data-id=fruit]", "berr")
      await search->WeftTesting.waitFor(
        () => search->WeftTesting.has("[data-id=fruit-list] [role=option]"),
      )
      let input = search->WeftTesting.query("[data-id=fruit]")->Option.getOrThrow
      let key = key =>
        WeftDom.Dom.dispatchEvent(
          input,
          %raw(`(key) => new KeyboardEvent("keydown", {key, bubbles: true, cancelable: true})`)(
            key,
          ),
        )
      key("ArrowDown")
      key("ArrowDown")
      key("Enter")
      await search->WeftTesting.waitFor(
        () => text(search, "[data-id=fruit-chosen]") == "Chose: blueberry",
      )
    },
  )
})
