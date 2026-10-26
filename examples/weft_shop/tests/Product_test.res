/***
A product's page: the offer for the picked variant (fetched again by itself for another), reviews
that arrive as a promise, rails and questions that stream (and fail) by themselves, adding to the
cart, and the wishlist.
*/

open Vitest
open ShopSupport

let app = useApp()

let reviewAuthors: unit => array<string> = %raw(`() =>
  [...document.querySelectorAll('[data-id=review-list] b')].map((node) => node.textContent.split(' ').at(-1))`)

/** Opens `url` with every gate open, once all of it has come, and hydrated. */
let openProduct = async (~url="/p/trail-runner") => {
  await app()->releaseAll
  let page = app()->open_(url)
  await page->WeftTesting.waitFor(() =>
    has(page, "[data-id=stock]") &&
    has(page, "[data-id=review-list]") &&
    has(page, "[data-id=carousel-also-bought]") &&
    has(page, "[data-id=questions]")
  )
  await hydratedAsServed(page)
  page
}

describe("a product's page", () => {
  testAsync(
    "streams the offer, the reviews, the rail and the questions, each by itself",
    async t => {
      let page = app()->open_("/p/trail-runner")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=product-name]"))
      t->expect(text(page, "[data-id=product-name]"))->Expect.toBe("Trail Runner")
      t->expect(has(page, "[data-id=offer-loading]"))->Expect.toBe(true)
      t->expect(has(page, "[data-id=reviews-loading]"))->Expect.toBe(true)
      t->expect(has(page, "[data-id=also-loading]"))->Expect.toBe(true)
      t->expect(has(page, "[data-id=questions-loading]"))->Expect.toBe(true)
      await hydratedAsServed(page)
      // The reviews first: a promise the server resolves after sending the page, read on the client.
      await app()->release("reviews:p1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=review-list]"))
      t->expect(text(page, "[data-id=review-summary]"))->Expect.toBe("3.1 out of 5, from 8 reviews")
      t->expect(has(page, "[data-id=offer-loading]"))->Expect.toBe(true)
      await app()->release("offer:p1-7")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=stock]"))
      t->expect(text(page, "[data-id=stock]"))->Expect.toBe("Size 7: only 1 left")
      t->expect(text(page, "[data-id=offer-price]"))->Expect.toBe("$129.00")
      await app()->release("rail:also-p1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=carousel-also-bought]"))
      t->expect(count("[data-id=carousel-also-bought] article"))->Expect.toBe(4)
      await app()->release("qa:p1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=questions]"))
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/p/trail-runner"])
      noWarnings(page)
    },
  )

  testAsync("hydrates as the server rendered it, whatever size of chunks it comes in", async t => {
    await app()->releaseAll
    let page = app()->open_(~delivery=EveryBytes(61), "/p/trail-runner")
    await page->WeftTesting.waitFor(
      () => has(page, "[data-id=review-list]") && has(page, "[data-id=questions]"),
    )
    await hydratedAsServed(page)
    // The gallery works.
    page->WeftTesting.click("[data-id=thumb-2]")
    t->expect(text(page, "[data-id=view-label]"))->Expect.toBe("Back")
    press("[data-id=gallery]", "ArrowRight")
    await page->WeftTesting.idle
    t->expect(text(page, "[data-id=view-label]"))->Expect.toBe("Detail")
    press("[data-id=gallery]", "ArrowRight")
    await page->WeftTesting.idle
    t->expect(text(page, "[data-id=view-label]"))->Expect.toBe("Front")
  })

  testAsync(
    "fetches another variant's offer by itself, keeping the old one until it's ready, and the quantity chosen",
    async t => {
      let page = await openProduct()
      await app()->hold("offer:p1-9")
      await app()->hold("offer:p1-7")
      page->WeftTesting.click("[data-id=variant-p1-9]")
      await page->WeftTesting.waitFor(
        () => attribute(page, "[data-id=offer]", "aria-busy") == Some("true"),
      )
      // The variant's picked at once; its offer's on its way, and the old one stays meanwhile.
      t
      ->expect(attribute(page, "[data-id=variant-p1-9]", "aria-pressed"))
      ->Expect.toBe(Some("true"))
      t->expect(text(page, "[data-id=stock]"))->Expect.toBe("Size 7: only 1 left")
      let reviews = page->WeftTesting.query("[data-id=review-list]")
      await app()->release("offer:p1-9")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=stock]") == "Size 9: 5 in stock")
      t->expect(attribute(page, "[data-id=offer]", "aria-busy"))->Expect.toBe(Some("false"))
      // Only the offer changed.
      t->expect(page->WeftTesting.query("[data-id=review-list]") == reviews)->Expect.toBe(true)
      await change(page, "[data-id=add-to-cart] select", "3")
      t
      ->expect(page->WeftTesting.query("[data-id=add-to-cart] select")->Option.map(Doc.value))
      ->Expect.toEqual(Some("3"))
      // Back to the size there's one of: the quantity the button kept is clamped to it.
      page->WeftTesting.click("[data-id=variant-p1-7]")
      await app()->release("offer:p1-7")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=stock]") == "Size 7: only 1 left")
      t
      ->expect(page->WeftTesting.query("[data-id=add-to-cart] select")->Option.map(Doc.value))
      ->Expect.toEqual(Some("1"))
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual([
        "/p/trail-runner",
        "/p/trail-runner/offer?sku=p1-9",
        "/p/trail-runner/offer?sku=p1-7",
      ])
      noWarnings(page)
    },
  )

  testAsync(
    "adds to the cart: the header's count follows at once, with a toast, and the server checks the stock",
    async t => {
      let page = await openProduct()
      page->WeftTesting.click("[data-id=variant-p1-9]")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=stock]") == "Size 9: 5 in stock")
      await change(page, "[data-id=add-to-cart] select", "3")
      page->WeftTesting.click("[data-id=add]")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=cart-button]") == "Cart (3)")
      t
      ->expect(text(page, "[data-id=toasts]"))
      ->Expect.toBe("Added 3 × Trail Runner to your cart×")
      t->expect((await app()->session).count)->Expect.toBe(3)
      // Three more than the five there are: the server says no, and the cart's as it was.
      page->WeftTesting.click("[data-id=add]")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=add-error]"))
      t->expect(text(page, "[data-id=add-error]"))->Expect.toBe("Not enough left of p1-9.")
      t->expect(text(page, "[data-id=cart-button]"))->Expect.toBe("Cart (3)")
      // The drawer (a modal dialog, in its place in the page) lists what's in the cart.
      page->WeftTesting.click("[data-id=cart-button]")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=cart-drawer][open]"))
      t
      ->expect(text(page, "[data-id=drawer-p1-9]"))
      ->Expect.toBe("Trail Runner (Size 9) × 3: $387.00")
      page->WeftTesting.click("[data-id=drawer-close]")
      await page->WeftTesting.waitFor(() => !has(page, "[data-id=cart-drawer][open]"))
      noWarnings(page)
    },
  )

  testAsync("can't add a variant that's sold out", async t => {
    let page = await openProduct(~url="/p/canvas-low")
    page->WeftTesting.click("[data-id=variant-p3-11]")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=stock]") == "Size 11: sold out")
    t->expect(text(page, "[data-id=add]"))->Expect.toBe("Sold out")
    t->expect(attribute(page, "[data-id=add]", "disabled"))->Expect.toBe(Some(""))
  })

  testAsync("sorts the reviews in a transition, and shows them all on request", async t => {
    let page = await openProduct()
    t->expect(reviewAuthors())->Expect.toEqual(["Grace", "Linus", "Barbara"])
    await change(page, "[data-id=review-order]", "highest")
    await page->WeftTesting.waitFor(() => reviewAuthors()->Array.at(0) == Some("Linus"))
    t->expect(reviewAuthors())->Expect.toEqual(["Linus", "Frances", "Margaret"])
    page->WeftTesting.click("[data-id=all-reviews]")
    t->expect(reviewAuthors()->Array.length)->Expect.toBe(8)
    t->expect(has(page, "[data-id=all-reviews]"))->Expect.toBe(false)
  })

  testAsync(
    "shows the questions service failing in that block alone, and Retry gets them",
    async t => {
      await app()->fail("qa:p1", "the questions service is unavailable")
      await app()->releaseAll
      let page = app()->open_("/p/trail-runner")
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=block-error-questions]") && has(page, "[data-id=review-list]"),
      )
      await page->WeftTesting.hydrated
      t
      ->expect(text(page, "[data-id=block-error-questions] p"))
      ->Expect.toBe("Couldn't load this: the questions service is unavailable")
      await app()->heal("qa:p1")
      await app()->release("qa:p1")
      page->WeftTesting.click("[data-id=retry-questions]")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=questions]"))
      t->expect(has(page, "[data-id=block-error-questions]"))->Expect.toBe(false)
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual(["/p/trail-runner", "/p/trail-runner/questions"])
    },
  )

  testAsync("that doesn't exist is the server's 404 page", async t => {
    await app()->releaseAll
    let page = app()->open_("/p/no-such-thing")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=not-found]"))
    await hydratedAsServed(page)
    t->expect(text(page, "[data-id=not-found]"))->Expect.toBe("Not found")
  })
})

describe("the wishlist", () => {
  testAsync(
    "asks a signed-out shopper to sign in, then saves at once, and on the server",
    async t => {
      let page = await openProduct()
      page->WeftTesting.click("[data-id=wishlist-p1]")
      await page->WeftTesting.waitFor(
        () => Doc.find("[data-id=signin-dialog][open]")->Option.isSome,
      )
      t
      ->expect(attribute(page, "[data-id=wishlist-p1]", "aria-pressed"))
      ->Expect.toBe(Some("false"))
      // Escape closes the dialog; the header opens it again.
      press("[data-id=signin-dialog]", "Escape")
      await page->WeftTesting.waitFor(
        () => Doc.find("[data-id=signin-dialog][open]")->Option.isNone,
      )
      await page->signIn("Ada")
      page->WeftTesting.click("[data-id=wishlist-p1]")
      t->expect(attribute(page, "[data-id=wishlist-p1]", "aria-pressed"))->Expect.toBe(Some("true"))
      await page->WeftTesting.waitFor(
        () => page->WeftTesting.pageRequests->Array.includes("/_weft/rpc/wishlist.toggle"),
      )
      await page->WeftTesting.settle
      t->expect(await app()->wishlist("Ada"))->Expect.toEqual(["p1"])
      // The same product, saved, in the "also bought" rail of another product's page.
      await page->WeftTesting.navigate("/p/city-sneaker")
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=carousel-also-bought] [data-id=wishlist-p1]"),
      )
      t
      ->expect(
        attribute(page, "[data-id=carousel-also-bought] [data-id=wishlist-p1]", "aria-pressed"),
      )
      ->Expect.toBe(Some("true"))
      // And on the account page.
      await page->WeftTesting.navigate("/account")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=wishlist] [data-id=card-p1]"))
      t->expect(text(page, "[data-id=account-title]"))->Expect.toBe("Ada's account")
      noWarnings(page)
    },
  )

  testAsync("puts the heart back when the server says no", async t => {
    let page = await openProduct()
    await page->signIn("Ada")
    // The server forgets the session (a restart, say): the next request is a new visitor's, who
    // isn't signed in.
    let _ = await app()->WeftTesting.callServer(control, "reset", [])
    page->WeftTesting.click("[data-id=wishlist-p1]")
    t->expect(attribute(page, "[data-id=wishlist-p1]", "aria-pressed"))->Expect.toBe(Some("true"))
    await page->WeftTesting.waitFor(
      () => attribute(page, "[data-id=wishlist-p1]", "aria-pressed") == Some("false"),
    )
    t->expect(text(page, "[data-id=toasts]")->String.includes("Sign in first."))->Expect.toBe(true)
  })
})
