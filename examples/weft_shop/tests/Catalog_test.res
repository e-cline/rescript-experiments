/***
The catalog: category pages (server-driven filters, results streamed beside them, more results from
an RPC whose answer is server-rendered cards) and search (suggestions as you type, results on
Enter).
*/

open Vitest
open ShopSupport

let app = useApp()

/** The names on the grid's cards, in order. */
let names: unit => array<string> = %raw(`() =>
  [...document.querySelectorAll('[data-id=grid] article h3')].map((node) => node.textContent)`)

/** Opens `url` with every gate open, once its grid and filters are in, and hydrated. */
let openCatalog = async (~url="/c/shoes") => {
  await app()->releaseAll
  let page = app()->open_(url)
  let search = url->String.startsWith("/search")
  await page->WeftTesting.waitFor(() =>
    has(page, "[data-id=grid]") && (search || has(page, "[data-id=facets]"))
  )
  await hydratedAsServed(page)
  page
}

describe("a category page", () => {
  testAsync("streams its blocks, its filters and its results, each by itself", async t => {
    let page = app()->open_("/c/shoes")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=results-loading]"))
    t->expect(has(page, "[data-id=facets-loading]"))->Expect.toBe(true)
    t->expect(has(page, "[data-id=banner-loading]"))->Expect.toBe(true)
    await hydratedAsServed(page)
    await app()->release("results:shoes")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=grid]"))
    t
    ->expect(names())
    ->Expect.toEqual(["Trail Runner", "City Sneaker", "Canvas Low", "Leather Boot"])
    t->expect(text(page, "[data-id=result-count]"))->Expect.toBe("Showing 4 of 8")
    t->expect(has(page, "[data-id=facets-loading]"))->Expect.toBe(true)
    await app()->release("facets:shoes")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=facets]"))
    t->expect(text(page, "[data-id=facet-color] legend"))->Expect.toBe("Colour")
    await app()->releasePrefix("layout:")
    await app()->releasePrefix("block:")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=hero-shoes-hero]"))
    t->expect(text(page, "[data-id=hero-shoes-hero] h1"))->Expect.toBe("Shoes")
    noWarnings(page)
  })

  testAsync(
    "loads more: the next page's cards, rendered on the server and sent by the RPC, their stock still streaming",
    async t => {
      await app()->releasePrefix("layout:")
      await app()->releasePrefix("block:")
      await app()->releasePrefix("facets:")
      await app()->releasePrefix("results:")
      await app()->releasePrefix("stock:p1")
      await app()->releasePrefix("stock:p2")
      await app()->releasePrefix("stock:p3")
      await app()->releasePrefix("stock:p4")
      let page = app()->open_("/c/shoes")
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=load-more]") && has(page, "[data-id=stock-p4]"),
      )
      await hydratedAsServed(page)
      page->WeftTesting.click("[data-id=load-more]")
      t->expect(text(page, "[data-id=load-more]"))->Expect.toBe("Loading…")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=card-p8]"))
      t->expect(names()->Array.length)->Expect.toBe(8)
      t->expect(text(page, "[data-id=result-count]"))->Expect.toBe("Showing 8 of 8")
      // The last page: no more to load.
      t->expect(has(page, "[data-id=load-more]"))->Expect.toBe(false)
      // The new cards' stock comes after the RPC has answered, each by itself.
      t->expect(text(page, "[data-id=stock-loading-p5]"))->Expect.toBe("Checking stock…")
      await app()->release("stock:p7")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=stock-p7]"))
      t->expect(text(page, "[data-id=stock-p7]"))->Expect.toBe("In stock")
      t->expect(has(page, "[data-id=stock-loading-p5]"))->Expect.toBe(true)
      // And the cards work: their prices follow the currency, their links navigate.
      await change(page, "[data-id=currency]", "GBP")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=card-p7] data") == "£94.01")
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual(["/c/shoes", "/_weft/rpc/catalog.more", "/_weft/rpc/prefs.setCurrency"])
      noWarnings(page)
    },
  )

  testAsync("filters the cards already here as you type, without fetching", async t => {
    let page = await openCatalog()
    let card = page->WeftTesting.query("[data-id=card-p1]")
    page->WeftTesting.input("[data-id=quick-filter]", "er")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=result-count]") == "Showing 3 of 8")
    t->expect(names())->Expect.toEqual(["Trail Runner", "City Sneaker", "Leather Boot"])
    // The cards that still match are the same nodes, the stock streamed into them and all.
    t->expect(page->WeftTesting.query("[data-id=card-p1]") == card)->Expect.toBe(true)
    page->WeftTesting.input("[data-id=quick-filter]", "zzz")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=no-results]"))
    page->WeftTesting.input("[data-id=quick-filter]", "")
    await page->WeftTesting.waitFor(() => names()->Array.length == 4)
    // Back, with their stock at once: it came with the page.
    t->expect(text(page, "[data-id=stock-p3]"))->Expect.toBe("In stock")
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/c/shoes"])
  })

  testAsync(
    "filters by navigating: the URL, the results and the filters change together, and the grid starts afresh",
    async t => {
      let page = await openCatalog()
      page->WeftTesting.click("[data-id=load-more]")
      await page->WeftTesting.waitFor(() => names()->Array.length == 8)
      page->WeftTesting.input("[data-id=quick-filter]", "boot")
      await page->WeftTesting.waitFor(() => names()->Array.length == 3)
      page->WeftTesting.click("[data-id=color-brown]")
      await page->WeftTesting.waitFor(
        () =>
          attribute(page, "[data-id=facets]", "aria-busy") == Some("false") &&
            names() == ["Leather Boot", "Slip-On Loafer"],
      )
      t->expect(text(page, "[data-id=result-count]"))->Expect.toBe("Showing 2 of 2")
      // A fresh grid, for the new filters: nothing typed, no page loaded.
      t
      ->expect(page->WeftTesting.query("[data-id=quick-filter]")->Option.map(Doc.value))
      ->Expect.toEqual(Some(""))
      t->expect(has(page, "[data-id=load-more]"))->Expect.toBe(false)
      t->expect(has(page, "[data-id=clear-filters]"))->Expect.toBe(true)
      t
      ->expect(text(page, "[data-id=facet-color]")->String.includes("brown (2)"))
      ->Expect.toBe(true)
      let navigation = await page->WeftTesting.navigation
      t->expect(navigation->WeftServer.Navigation.url)->Expect.toBe("/c/shoes?color=brown")
      // Another colour, then the sort order.
      page->WeftTesting.click("[data-id=color-green]")
      await page->WeftTesting.waitFor(() => names()->Array.length == 4)
      await change(page, "[data-id=sort]", "price-desc")
      await page->WeftTesting.waitFor(() => names()->Array.at(0) == Some("Leather Boot"))
      t
      ->expect(names())
      ->Expect.toEqual(["Leather Boot", "Hiking Boot", "Trail Runner", "Slip-On Loafer"])
      t
      ->expect(navigation->WeftServer.Navigation.url)
      ->Expect.toBe("/c/shoes?color=brown&color=green&sort=price-desc")
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual([
        "/c/shoes",
        "/_weft/rpc/catalog.more",
        "/c/shoes?color=brown",
        "/c/shoes?color=brown&color=green",
        "/c/shoes?color=brown&color=green&sort=price-desc",
      ])
      noWarnings(page)
    },
  )

  testAsync("keeps showing the results it has while the new ones are fetched", async t => {
    let page = await openCatalog()
    await app()->hold("results:shoes")
    page->WeftTesting.click("[data-id=toggle-instock]")
    await page->WeftTesting.waitFor(
      () => attribute(page, "[data-id=facets]", "aria-busy") == Some("true"),
    )
    await page->WeftTesting.idle
    // A navigation renders in a transition: the old results stay, no fallback over them.
    t->expect(names()->Array.length)->Expect.toBe(4)
    t->expect(has(page, "[data-id=results-loading]"))->Expect.toBe(false)
    await app()->release("results:shoes")
    await page->WeftTesting.waitFor(
      () => attribute(page, "[data-id=facets]", "aria-busy") == Some("false"),
    )
    t->expect(text(page, "[data-id=result-count]"))->Expect.toBe("Showing 4 of 8")
    t->expect(attribute(page, "[data-id=toggle-instock]", "checked"))->Expect.toBe(None)
    t
    ->expect(
      page
      ->WeftTesting.query("[data-id=toggle-instock]")
      ->Option.map(element => WeftDom.Dom.getProperty(element, "checked")->Obj.magic),
    )
    ->Expect.toEqual(Some(true))
  })

  testAsync("narrows by price, and the range resets when the filters are cleared", async t => {
    let page = await openCatalog()
    let low = "[data-id=price-from]"
    let high = "[data-id=price-to]"
    t->expect(page->WeftTesting.query(low)->Option.map(Doc.value))->Expect.toEqual(Some("59"))
    page->WeftTesting.input(low, "80")
    page->WeftTesting.input(high, "130")
    page->WeftTesting.click("[data-id=apply-price]")
    await page->WeftTesting.waitFor(() => !has(page, "[data-id=load-more]"))
    t
    ->expect(names())
    ->Expect.toEqual(["Trail Runner", "City Sneaker", "Court Classic", "Slip-On Loafer"])
    t->expect(page->WeftTesting.query(low)->Option.map(Doc.value))->Expect.toEqual(Some("80"))
    page->WeftTesting.click("[data-id=clear-filters]")
    await page->WeftTesting.waitFor(() => !has(page, "[data-id=clear-filters]"))
    t->expect(page->WeftTesting.query(low)->Option.map(Doc.value))->Expect.toEqual(Some("59"))
    t->expect(page->WeftTesting.query(high)->Option.map(Doc.value))->Expect.toEqual(Some("190"))
    t->expect(names()->Array.length)->Expect.toBe(4)
  })

  testAsync("that doesn't exist is the server's 404 page", async t => {
    await app()->releaseAll
    let page = app()->open_("/c/hats")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=not-found]"))
    await hydratedAsServed(page)
    t->expect(text(page, "[data-id=not-found]"))->Expect.toBe("Not found")
  })
})

describe("search", () => {
  testAsync("suggests as you type, and a newer query cancels the older one's request", async t => {
    let page = await openCatalog()
    await app()->hold("search:suggest")
    page->WeftTesting.input("[data-id=search-input]", "bo")
    let first = await app()->nextWaiter(page, "search:suggest")
    page->WeftTesting.input("[data-id=search-input]", "boo")
    let second = await app()->nextWaiter(page, "search:suggest", ~except=[first])
    // The first's request was cancelled: the server sees it abandoned, and it never answers.
    t->expect(await app()->abandonedSoon(page, first))->Expect.toBe(true)
    await app()->release(second)
    await page->WeftTesting.waitFor(() => has(page, "[role=\"listbox\"]"))
    t
    ->expect(text(page, "[role=\"listbox\"]"))
    ->Expect.toBe("Leather BootshoesRain BootshoesHiking Bootshoes")
    // A suggestion is a link to its product.
    page->WeftTesting.click("[data-id=suggestion-rain-boot]")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=product-name]"))
    t->expect(text(page, "[data-id=product-name]"))->Expect.toBe("Rain Boot")
    t->expect(has(page, "[role=\"listbox\"]"))->Expect.toBe(false)
  })

  testAsync("shows the results on Enter, keeping what was typed in the header's box", async t => {
    let page = await openCatalog()
    page->WeftTesting.input("[data-id=search-input]", "bag")
    let form = page->WeftTesting.query("[data-id=search]")->Option.getOrThrow
    WeftDom.Dom.dispatchEvent(
      form,
      WeftDom.Dom.Event.make("submit", {bubbles: true, cancelable: true}),
    )
    await page->WeftTesting.waitFor(
      () => has(page, "[data-id=search-title]") && has(page, "[data-id=grid]"),
    )
    t->expect(text(page, "[data-id=search-title]"))->Expect.toBe("Results for “bag”")
    t->expect(text(page, "[data-id=result-count]"))->Expect.toBe("Showing 4 of 8")
    t
    ->expect(page->WeftTesting.query("[data-id=search-input]")->Option.map(Doc.value))
    ->Expect.toEqual(Some("bag"))
    // More results, for the search, from the same RPC.
    page->WeftTesting.click("[data-id=load-more]")
    await page->WeftTesting.waitFor(() => names()->Array.length == 8)
    t->expect(names()->Array.at(-1))->Expect.toEqual(Some("Roll-Top Pack"))
    t
    ->expect(
      page->WeftTesting.pageRequests->Array.filter(url => !(url->String.includes("suggest"))),
    )
    ->Expect.toEqual(["/c/shoes", "/search?q=bag", "/_weft/rpc/catalog.more"])
  })

  testAsync("opened directly, renders the results on the server", async t => {
    let page = await openCatalog(~url="/search?q=white")
    t->expect(names())->Expect.toEqual(["City Sneaker", "Court Classic", "Windbreaker", "Tote"])
    t
    ->expect(page->WeftTesting.query("[data-id=search-input]")->Option.map(Doc.value))
    ->Expect.toEqual(Some("white"))
  })
})
