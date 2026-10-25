/***
The home page: server-driven (the CMS's blocks, personalised per shopper), streamed (the layout, then
each block, then each card's stock, every one under a boundary of its own), and changed at runtime
(a refresh brings the server's newer layout over the page).
*/

open Vitest
open ShopSupport

let app = useApp()

let entrypoint = name => `@e-cline/weft_shop_example/src/client/${name}.res#`

/** The ids of the home page's blocks, in order. */
let blockIds: WeftTesting.page => array<string> = %raw(`page =>
  [...page.container.querySelectorAll('[data-id=blocks-home] > *')].map((node) => node.dataset.id)`)

let allBlocks = [
  "block-hero",
  "block-promo-a",
  "block-featured",
  "block-live",
  "block-categories",
  "tabs-tabs",
  "columns-bottom",
  "block-recent",
]

/** Opens the home page with every gate open, once it has all rendered, and hydrated. */
let openHome = async () => {
  await app()->releaseAll
  let page = app()->open_("/")
  await page->WeftTesting.waitFor(() =>
    has(page, "[data-id=hero-hero]") &&
    has(page, "[data-id=carousel-tab-bags]") &&
    has(page, "[data-id=stock-p20]")
  )
  await hydratedAsServed(page)
  page
}

describe("streaming", () => {
  testAsync(
    "sends the shell, then the layout, then each block as its service answers, in any order",
    async t => {
      let page = app()->open_("/")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=home-loading]"))
      // The header is in the shell, and works before anything else has come.
      t->expect(text(page, "[data-id=cart-button]"))->Expect.toBe("Cart (0)")
      await hydratedAsServed(page)
      await app()->release("layout:home")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=blocks-home]"))
      t->expect(blockIds(page))->Expect.toEqual(allBlocks)
      t
      ->expect(
        ["hero", "promo-a", "featured", "live", "categories"]->Array.every(
          id => has(page, `[data-id=loading-${id}]`),
        ),
      )
      ->Expect.toBe(true)
      // The featured rail, before the hero above it, and its cards before their stock.
      await app()->release("rail:featured")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=carousel-featured]"))
      t->expect(has(page, "[data-id=loading-hero]"))->Expect.toBe(true)
      t->expect(text(page, "[data-id=stock-loading-p1]"))->Expect.toBe("Checking stock…")
      await app()->release("stock:p1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=stock-p1]"))
      t->expect(text(page, "[data-id=stock-p1]"))->Expect.toBe("In stock")
      t->expect(has(page, "[data-id=stock-loading-p10]"))->Expect.toBe(true)
      await app()->release("block:hero")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=hero-hero]"))
      t->expect(text(page, "[data-id=hero-hero] h1"))->Expect.toBe("Made to last")
      // A tab's rail streams by itself, hidden or not.
      await app()->release("rail:tab-outerwear")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=carousel-tab-outerwear]"))
      t->expect(has(page, "[data-id=loading-tab-shoes]"))->Expect.toBe(true)
      await app()->releaseAll
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=stock-p20]") && has(page, "[data-id=newsletter]"),
      )
      // One request: the page, and everything streamed into it.
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/"])
      noWarnings(page)
    },
  )

  testAsync("hydrates every block's HTML, whatever size of chunks it comes in", async t => {
    await app()->releaseAll
    let page = app()->open_(~delivery=EveryBytes(97), "/")
    await page->WeftTesting.waitFor(
      () => has(page, "[data-id=stock-p20]") && has(page, "[data-id=newsletter]"),
    )
    await hydratedAsServed(page)
    t
    ->expect(mainChildren(page))
    ->Expect.toEqual(["<!--$-->", "div[data-id=blocks-home]", "<!--/$-->"])
  })

  testAsync(
    "hydrates a boundary whose content arrives while its entrypoints' chunks are still loading, rendering nothing twice",
    async t => {
      // The tabs' chunk is slow: the blocks arrive, after the bootstrap, while it's loading.
      let page = app()->open_("/")
      page->WeftTesting.holdLoads(~matching="Tabs")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=home-loading]"))
      await page->WeftTesting.hydrated
      await app()->releaseAll
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=blocks-home]") && has(page, "[data-id=stock-p20]"),
      )
      await page->WeftTesting.idle
      // The server's blocks, still unhydrated: nothing of the client's beside them.
      t
      ->expect(mainChildren(page))
      ->Expect.toEqual(["<!--$-->", "div[data-id=blocks-home]", "<!--/$-->"])
      t->expect(page->WeftTesting.renderCount(entrypoint("Tabs")))->Expect.toBe(0)
      page->WeftTesting.releaseLoads
      await hydratedAsServed(page)
      t
      ->expect(mainChildren(page))
      ->Expect.toEqual(["<!--$-->", "div[data-id=blocks-home]", "<!--/$-->"])
      t->expect(count("[data-id=tabs-tabs]"))->Expect.toBe(1)
      // And the tabs work.
      page->WeftTesting.click("#tabs-tabs-tab-2")
      t->expect(attribute(page, "#tabs-tabs-panel-2", "hidden"))->Expect.toBe(None)
    },
  )

  testAsync(
    "stops the services a page was waiting on when the shopper navigates away, and shows none of it",
    async t => {
      await app()->releasePrefix("layout:")
      await app()->releasePrefix("facets:")
      await app()->releasePrefix("results:")
      await app()->releasePrefix("block:")
      await app()->releasePrefix("stock:")
      let page = app()->open_("/c/shoes")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=grid]"))
      await page->WeftTesting.hydrated
      // To the home page, whose rails are slow, then on to the bags before they've come.
      page->WeftTesting.click("[data-id=logo]")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=blocks-home]"))
      t->expect(has(page, "[data-id=loading-featured]"))->Expect.toBe(true)
      page->WeftTesting.click("[data-id=nav-bags]")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=card-p17]"))
      // The server saw the home page's rails abandoned when the client went away.
      let rec abandonedRails = async tries => {
        let found = (await app()->abandoned)->Array.filter(id => id->String.startsWith("rail:"))
        Array.length(found) >= 4 || tries == 0
          ? found
          : {
              await page->WeftTesting.idle
              await abandonedRails(tries - 1)
            }
      }
      let rails = await abandonedRails(50)
      t->expect(rails->Array.some(id => id->String.startsWith("rail:featured#")))->Expect.toBe(true)
      t->expect(rails->Array.some(id => id->String.startsWith("rail:tab-bags#")))->Expect.toBe(true)
      await app()->releaseAll
      await page->WeftTesting.settle
      t->expect(has(page, "[data-id=carousel-featured]"))->Expect.toBe(false)
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/c/shoes", "/", "/c/bags"])
      noWarnings(page)
    },
  )
})

describe("blocks", () => {
  testAsync("work once hydrated: the countdown ticks, carousels page, tabs switch", async t => {
    let page = await openHome()
    let countdown = text(page, "[data-id=countdown-promo-a]")
    t->expect(countdown->String.startsWith("Ends in 1h 29m"))->Expect.toBe(true)
    t->expect(text(page, "[data-id=position-featured]"))->Expect.toBe("1–4 of 6")
    page->WeftTesting.click("[data-id=next-featured]")
    t->expect(text(page, "[data-id=position-featured]"))->Expect.toBe("5–6 of 6")
    t->expect(attribute(page, "#tabs-tabs-panel-1", "hidden"))->Expect.toBe(Some(""))
    page->WeftTesting.click("#tabs-tabs-tab-1")
    t->expect(attribute(page, "#tabs-tabs-panel-1", "hidden"))->Expect.toBe(None)
    t->expect(attribute(page, "#tabs-tabs-panel-0", "hidden"))->Expect.toBe(Some(""))
    t->expect(attribute(page, "#tabs-tabs-tab-1", "aria-selected"))->Expect.toBe(Some("true"))
    await page->WeftTesting.waitFor(
      ~timeout=3000,
      () => text(page, "[data-id=countdown-promo-a]") != countdown,
    )
  })

  testAsync(
    "change with the server's layout on a refresh: moved, added and removed, each keeping its state",
    async t => {
      let page = await openHome()
      page->WeftTesting.click("#tabs-tabs-tab-1")
      page->WeftTesting.click("[data-id=next-featured]")
      let tabs = page->WeftTesting.query("[data-id=tabs-tabs]")
      let featured = page->WeftTesting.query("[data-id=carousel-featured]")
      let tabsRenders = page->WeftTesting.renderCount(entrypoint("Tabs"))
      await app()->move(~page="home", "tabs", 0)
      await app()->insertText(~page="home", "notice", 2, "Free returns, always")
      await app()->removeBlock(~page="home", "categories")
      await app()->setHeroTitle(~page="home", "Built to last")
      await page->WeftTesting.refresh
      await page->WeftTesting.waitFor(() => has(page, "[data-id=text-notice]"))
      t
      ->expect(blockIds(page))
      ->Expect.toEqual([
        "tabs-tabs",
        "block-hero",
        "block-notice",
        "block-promo-a",
        "block-featured",
        "block-live",
        "columns-bottom",
        "block-recent",
      ])
      t->expect(text(page, "[data-id=hero-hero] h1"))->Expect.toBe("Built to last")
      // The same tabs and rail, moved, not made again: their state is as it was.
      t->expect(page->WeftTesting.query("[data-id=tabs-tabs]") == tabs)->Expect.toBe(true)
      t
      ->expect(page->WeftTesting.query("[data-id=carousel-featured]") == featured)
      ->Expect.toBe(true)
      t->expect(attribute(page, "#tabs-tabs-tab-1", "aria-selected"))->Expect.toBe(Some("true"))
      t->expect(text(page, "[data-id=position-featured]"))->Expect.toBe("5–6 of 6")
      t->expect(page->WeftTesting.renderCount(entrypoint("Tabs")) > tabsRenders)->Expect.toBe(true)
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/", "/"])
      noWarnings(page)
    },
  )

  testAsync("show each half of the experiment its own promotion, in the same place", async t => {
    let page = await openHome()
    t
    ->expect(text(page, "[data-id=promo-promo-a] > p"))
    ->Expect.toBe("10% off everything with code WEFT10")
    await app()->setBucket("b")
    await page->WeftTesting.refresh
    await page->WeftTesting.waitFor(() => has(page, "[data-id=promo-promo-b]"))
    t
    ->expect(text(page, "[data-id=promo-promo-b] > p"))
    ->Expect.toBe("20% off orders over $100 with code LOOM20")
    t->expect(blockIds(page)->Array.at(1))->Expect.toEqual(Some("block-promo-b"))
  })

  testAsync(
    "fail by themselves: the rest of the page is shown, and Retry fetches the block again",
    async t => {
      await app()->fail("rail:featured", "the catalogue service is down")
      await app()->releaseAll
      let page = app()->open_("/")
      await page->WeftTesting.waitFor(
        () =>
          has(page, "[data-id=block-error-featured]") &&
          has(page, "[data-id=hero-hero]") &&
          has(page, "[data-id=stock-p20]"),
      )
      // The failed block's boundary is the client's to render (its error is thrown again there,
      // for the frame's error boundary to catch); the rest is the server's.
      await page->WeftTesting.hydrated
      t
      ->expect(text(page, "[data-id=block-error-featured] p"))
      ->Expect.toBe("Couldn't load this: the catalogue service is down")
      t->expect(has(page, "[data-id=carousel-tab-shoes]"))->Expect.toBe(true)
      // Still down: Retry shows the error again.
      page->WeftTesting.click("[data-id=retry-featured]")
      await page->WeftTesting.waitFor(
        () => page->WeftTesting.pageRequests->Array.includes("/blocks/home/featured"),
      )
      await page->WeftTesting.settle
      t->expect(has(page, "[data-id=block-error-featured]"))->Expect.toBe(true)
      // Back up.
      await app()->heal("rail:featured")
      await app()->release("rail:featured")
      page->WeftTesting.click("[data-id=retry-featured]")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=carousel-featured]"))
      t->expect(has(page, "[data-id=block-error-featured]"))->Expect.toBe(false)
      t->expect(text(page, "[data-id=stock-p1]"))->Expect.toBe("In stock")
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual(["/", "/blocks/home/featured", "/blocks/home/featured"])
    },
  )

  testAsync("that are live refetch themselves, and show the server's newer stock", async t => {
    await app()->setLiveEvery(1)
    let page = await openHome()
    t->expect(text(page, "[data-id=left-p3]"))->Expect.toBe(" 20 left")
    await app()->setStock("p3-7", 0)
    await page->WeftTesting.waitFor(
      ~timeout=3000,
      () => text(page, "[data-id=left-p3]") == " 15 left",
    )
    t
    ->expect(page->WeftTesting.pageRequests->Array.includes("/blocks/home/live"))
    ->Expect.toBe(true)
    // Only the live block is fetched again.
    t
    ->expect(
      page->WeftTesting.pageRequests->Array.every(url => url == "/" || url == "/blocks/home/live"),
    )
    ->Expect.toBe(true)
  })
})

describe("the harness", () => {
  testAsync("closes a page when the next opens: its live block stops refreshing", async t => {
    await app()->setLiveEvery(1)
    let first = await openHome()
    await first->WeftTesting.waitFor(
      ~timeout=3000,
      () => first->WeftTesting.pageRequests->Array.includes("/blocks/home/live"),
    )
    let page = app()->open_("/c/shoes")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=grid]"))
    await Promise.make((resolve, _) => setTimeout(() => resolve(), 1500)->ignore)
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/c/shoes"])
  })
})

describe("personalised", () => {
  testAsync(
    "for a shopper who signs in: welcomed, recommended to, and shown what they've looked at",
    async t => {
      await app()->releaseAll
      let page = app()->open_("/p/canvas-low")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=product-name]"))
      await page->WeftTesting.hydrated
      // Signing in, from the dialog.
      page->WeftTesting.click("[data-id=sign-in]")
      await page->WeftTesting.waitFor(() => Doc.find("[data-id=signin-dialog]")->Option.isSome)
      inputAnywhere("[data-id=signin-dialog] input", "Ada")
      submitAnywhere("[data-id=signin-dialog] form")
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=account-menu]")->String.includes("Hi, Ada"),
      )
      t->expect(Doc.find("[data-id=signin-dialog]"))->Expect.toBe(None)
      await page->WeftTesting.navigate("/")
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=hero-welcome]") && has(page, "[data-id=carousel-recent]"),
      )
      t->expect(text(page, "[data-id=hero-welcome] h1"))->Expect.toBe("Welcome back, Ada")
      t->expect(has(page, "[data-id=hero-hero]"))->Expect.toBe(false)
      // Recommended: what's bought with what they looked at, but not that.
      await page->WeftTesting.waitFor(() => has(page, "[data-id=carousel-for-you]"))
      t->expect(has(page, "[data-id=card-p3]"))->Expect.toBe(true)
      t
      ->expect(text(page, "[data-id=carousel-for-you]")->String.includes("Canvas Low"))
      ->Expect.toBe(false)
      t
      ->expect(text(page, "[data-id=carousel-recent]")->String.includes("Canvas Low"))
      ->Expect.toBe(true)
      // Nothing bought yet: no rail to buy again.
      t->expect(has(page, "[data-id=carousel-buy-again]"))->Expect.toBe(false)
      let session = await app()->session
      t->expect((session.user, session.viewed))->Expect.toEqual(("Ada", ["p3"]))
      noWarnings(page)
    },
  )

  testAsync(
    "with recommendations that fail now and then, which Retry gets once they're back",
    async t => {
      await app()->releaseAll
      await app()->fail("recs:for-you", "the recommendations service timed out")
      let page = app()->open_("/")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=hero-hero]"))
      await page->WeftTesting.hydrated
      page->WeftTesting.click("[data-id=sign-in]")
      await page->WeftTesting.waitFor(() => Doc.find("[data-id=signin-dialog]")->Option.isSome)
      inputAnywhere("[data-id=signin-dialog] input", "Grace")
      submitAnywhere("[data-id=signin-dialog] form")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=block-error-for-you]"))
      t
      ->expect(text(page, "[data-id=block-error-for-you] p"))
      ->Expect.toBe("Couldn't load this: the recommendations service timed out")
      t->expect(has(page, "[data-id=hero-welcome]"))->Expect.toBe(true)
      await app()->heal("recs:for-you")
      await app()->release("recs:for-you")
      page->WeftTesting.click("[data-id=retry-for-you]")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=carousel-for-you]"))
      noWarnings(page)
    },
  )
})

describe("prices", () => {
  testAsync(
    "change currency everywhere at once, with nothing fetched, and stay changed on the next page",
    async t => {
      let page = await openHome()
      t->expect(text(page, "[data-id=card-p1] data"))->Expect.toBe("$129.00")
      await change(page, "[data-id=currency]", "EUR")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=card-p1] data") == "€118.68")
      // Every price, in every block and tab, hidden or not.
      t
      ->expect(text(page, "[data-id=carousel-tab-bags] [data-id=card-p17] data"))
      ->Expect.toBe("€146.28")
      t->expect(text(page, "[data-id=live-p3] data"))->Expect.toBe("€67.85 €54.28")
      await page->WeftTesting.waitFor(
        () => page->WeftTesting.pageRequests->Array.includes("/_weft/rpc/prefs.setCurrency"),
      )
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual(["/", "/_weft/rpc/prefs.setCurrency"])
      t->expect((await app()->session).currency)->Expect.toBe("EUR")
      // A new page load: the server renders it in euros.
      let page = app()->open_("/c/shoes")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=card-p1]"))
      t->expect(text(page, "[data-id=card-p1] data"))->Expect.toBe("€118.68")
      await hydratedAsServed(page)
    },
  )
})
