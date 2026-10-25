/***
The cart (quantities changed at once, totals from the server), promo codes, checking out, the order
page that refreshes itself, and the session behind all of it (a cookie, signing in and out).
*/

open Vitest
open ShopSupport

let app = useApp()

let entrypoint = name => `@e-cline/weft_shop_example/src/client/${name}.res#`

/** Opens the cart page with `items` (SKU and quantity) in the cart, hydrated, every gate open. */
let openCart = async items => {
  await app()->releaseAll
  // A first page, for a session.
  let page = app()->open_("/c/bags")
  await page->WeftTesting.waitFor(() => has(page, "#grid"))
  for i in 0 to Array.length(items) - 1 {
    let (sku, quantity) = items->Array.getUnsafe(i)
    await app()->addToCart(sku, quantity)
  }
  let page = app()->open_("/cart")
  await page->WeftTesting.waitFor(() =>
    has(page, "#summary") && (items == [] || has(page, "#cart-lines"))
  )
  await hydratedAsServed(page)
  page
}

let quantity = (page, sku) => text(page, `#quantity-${sku}`)

/** Fills the checkout's address step with `fields` (by input name). */
let fill = (page, fields) =>
  fields->Array.forEach(((name, value)) => page->WeftTesting.input(`input[name=${name}]`, value))

describe("the cart", () => {
  testAsync("lists the session's cart, with the totals worked out on the server", async t => {
    let page = await openCart([("p1-9", 2), ("p19-one", 1)])
    t->expect(quantity(page, "p1-9"))->Expect.toBe("2")
    t->expect(text(page, "#total-p1-9"))->Expect.toBe("$258.00")
    t->expect(text(page, "#summary-subtotal"))->Expect.toBe("$307.00")
    t->expect(text(page, "#summary-points"))->Expect.toBe("307")
    t->expect(text(page, "#cart-button"))->Expect.toBe("Cart (3)")
  })

  testAsync(
    "changes a quantity at once, then takes the server's cart, and its totals follow by themselves",
    async t => {
      let page = await openCart([("p1-9", 2), ("p19-one", 1)])
      await app()->hold("block:summary")
      page->WeftTesting.click("#more-p19-one")
      // At once, before the server has answered.
      t->expect(quantity(page, "p19-one"))->Expect.toBe("2")
      await page->WeftTesting.waitFor(() => text(page, "#cart-button") == "Cart (4)")
      // The totals are being fetched again (the cart's version went up): the old ones stay meanwhile.
      await page->WeftTesting.waitFor(
        () => attribute(page, "#summary-frame", "aria-busy") == Some("true"),
      )
      t->expect(text(page, "#summary-subtotal"))->Expect.toBe("$307.00")
      await app()->release("block:summary")
      await page->WeftTesting.waitFor(() => text(page, "#summary-subtotal") == "$356.00")
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual(["/cart", "/_weft/rpc/cart.setQuantity", "/cart/summary"])
      // Only the totals' frame fetched; the lines didn't come from a refresh.
      t->expect(page->WeftTesting.renderCount(entrypoint("PromoForm")))->Expect.toBe(1)
      noWarnings(page)
    },
  )

  testAsync("puts the quantity back when the server says there aren't that many", async t => {
    let page = await openCart([("p1-9", 5)])
    page->WeftTesting.click("#more-p1-9")
    t->expect(quantity(page, "p1-9"))->Expect.toBe("6")
    await page->WeftTesting.waitFor(() => quantity(page, "p1-9") == "5")
    t->expect(text(page, "#toasts"))->Expect.toBe("Not enough left of p1-9.×")
    t->expect((await app()->session).count)->Expect.toBe(5)
  })

  testAsync(
    "empties, line by line, and there's then nothing to check out: checkout redirects to the cart",
    async t => {
      let page = await openCart([("p1-9", 1), ("p19-one", 1)])
      page->WeftTesting.click("#remove-p1-9")
      await page->WeftTesting.waitFor(() => !has(page, "#line-p1-9"))
      page->WeftTesting.click("#less-p19-one")
      await page->WeftTesting.waitFor(() => has(page, "#cart-empty"))
      await page->WeftTesting.waitFor(() => text(page, "#cart-button") == "Cart (0)")
      let before = page->WeftTesting.pageRequests->Array.length
      page->WeftTesting.click("#checkout-link")
      await page->WeftTesting.waitFor(
        () => page->WeftTesting.pageRequests->Array.length == before + 2,
      )
      await page->WeftTesting.settle
      t
      ->expect(page->WeftTesting.pageRequests->Array.slice(~start=before))
      ->Expect.toEqual(["/checkout", "/cart"])
      // The cart, at its own URL: in the navigation, and in the address bar.
      t->expect(has(page, "#cart-empty"))->Expect.toBe(true)
      t->expect(has(page, "#checkout-title"))->Expect.toBe(false)
      t->expect(await urlOf(page))->Expect.toBe("/cart")
      t->expect(addressBar())->Expect.toBe("/cart")
      t->expect((await app()->session).count)->Expect.toBe(0)
    },
  )

  testAsync(
    "takes promo codes: an empty one isn't sent, unknown and expired ones are refused, a good one is applied",
    async t => {
      let page = await openCart([("p1-9", 2), ("p19-one", 1)])
      page->WeftTesting.input("#promo input", "   ")
      submitAnywhere("#promo")
      await page->WeftTesting.waitFor(() => has(page, "#promo-message"))
      t->expect(text(page, "#promo-message"))->Expect.toBe("That code isn't one of ours.")
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/cart"])
      page->WeftTesting.input("#promo input", "nope")
      submitAnywhere("#promo")
      await page->WeftTesting.waitFor(
        () => page->WeftTesting.pageRequests->Array.includes("/_weft/rpc/cart.applyPromo"),
      )
      await page->WeftTesting.settle
      t->expect(text(page, "#promo-message"))->Expect.toBe("That code isn't one of ours.")
      page->WeftTesting.input("#promo input", "summer")
      submitAnywhere("#promo")
      await page->WeftTesting.waitFor(
        () => text(page, "#promo-message") == "That code has expired.",
      )
      page->WeftTesting.input("#promo input", " weft10 ")
      submitAnywhere("#promo")
      await page->WeftTesting.waitFor(() => text(page, "#promo-message") == "Applied WEFT10")
      await page->WeftTesting.waitFor(() => has(page, "#summary-discount"))
      t->expect(text(page, "#summary-discount"))->Expect.toBe("-$30.70")
      t->expect(text(page, "#summary-total"))->Expect.toBe("$276.30")
      t->expect((await app()->session).promo)->Expect.toBe("WEFT10")
    },
  )
})

describe("checking out", () => {
  testAsync("checks the address before going on, without asking the server", async t => {
    let page = await openCart([("p1-9", 2), ("p19-one", 1)])
    page->WeftTesting.click("#checkout-link")
    await page->WeftTesting.waitFor(() => has(page, "#address-step"))
    submitAnywhere("#checkout-form")
    await page->WeftTesting.idle
    t->expect(text(page, "#checkout-error"))->Expect.toBe("Fill in the name.")
    fill(
      page,
      [("name", "Ada"), ("street", "1 Loop Lane"), ("city", "Testville"), ("postcode", "1234")],
    )
    submitAnywhere("#checkout-form")
    await page->WeftTesting.idle
    t->expect(text(page, "#checkout-error"))->Expect.toBe("A postcode is five digits.")
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/cart", "/checkout"])
    // The labels are linked by IDs from `useId`.
    let nameInput = page->WeftTesting.query("input[name=name]")->Option.getOrThrow
    let id = WeftDom.Dom.getAttribute(nameInput, "id")->Nullable.toOption->Option.getOrThrow
    t->expect(has(page, `label[for="${id}"]`))->Expect.toBe(true)
  })

  testAsync(
    "places the order, and goes on to its page, which streams its estimate and refreshes itself until it's delivered",
    async t => {
      await app()->setPoll(30)
      let page = await openCart([("p1-9", 2), ("p19-one", 1)])
      page->WeftTesting.click("#checkout-link")
      await page->WeftTesting.waitFor(() => has(page, "#address-step"))
      fill(
        page,
        [("name", "Ada"), ("street", "1 Loop Lane"), ("city", "Testville"), ("postcode", "12345")],
      )
      submitAnywhere("#checkout-form")
      await page->WeftTesting.waitFor(() => has(page, "#delivery-step"))
      page->WeftTesting.click("#delivery-express")
      page->WeftTesting.input("#gift-note", "Happy birthday")
      submitAnywhere("#checkout-form")
      await page->WeftTesting.waitFor(() => has(page, "#review-step"))
      t->expect(text(page, "#review-total"))->Expect.toBe("Total: $322.00")
      await app()->hold("estimate:o1001")
      submitAnywhere("#checkout-form")
      await page->WeftTesting.waitFor(() => has(page, "#order-title"))
      t->expect(text(page, "#order-title"))->Expect.toBe("Order o1001")
      t->expect(text(page, "#order-total"))->Expect.toBe("$322.00")
      t->expect(text(page, "#cart-button"))->Expect.toBe("Cart (0)")
      t->expect(has(page, "#estimate-loading"))->Expect.toBe(true)
      let navigation = await page->WeftTesting.navigation
      t->expect(navigation->WeftServer.Navigation.url)->Expect.toBe("/orders/o1001")
      // It refreshes itself: the server's newer status comes in, and its estimate when it's ready.
      await app()->release("estimate:o1001")
      await page->WeftTesting.waitFor(() => text(page, "#estimate") == "Arriving in 3–5 days.")
      await app()->advanceOrder("o1001")
      await page->WeftTesting.waitFor(() => text(page, "#order-status") == "Status: Packed")
      await app()->advanceOrder("o1001")
      await page->WeftTesting.waitFor(() => text(page, "#order-status") == "Status: Shipped")
      await page->WeftTesting.waitFor(() => text(page, "#estimate") == "Arriving tomorrow.")
      await app()->advanceOrder("o1001")
      await page->WeftTesting.waitFor(() => text(page, "#order-status") == "Status: Delivered")
      // Delivered: it stops.
      await page->WeftTesting.settle
      let requests = Array.length(page->WeftTesting.pageRequests)
      await page->WeftTesting.idle
      await Promise.make((resolve, _) => setTimeout(() => resolve(), 120)->ignore)
      t->expect(Array.length(page->WeftTesting.pageRequests))->Expect.toBe(requests)
      t->expect(await app()->stock("p1-9"))->Expect.toBe(3)
      noWarnings(page)
    },
  )

  testAsync("says which item ran out when someone else bought the last one first", async t => {
    let page = await openCart([("p1-7", 1), ("p19-one", 1)])
    page->WeftTesting.click("#checkout-link")
    await page->WeftTesting.waitFor(() => has(page, "#address-step"))
    fill(
      page,
      [("name", "Ada"), ("street", "1 Loop Lane"), ("city", "Testville"), ("postcode", "12345")],
    )
    submitAnywhere("#checkout-form")
    await page->WeftTesting.waitFor(() => has(page, "#delivery-step"))
    submitAnywhere("#checkout-form")
    await page->WeftTesting.waitFor(() => has(page, "#review-step"))
    await app()->setStock("p1-7", 0)
    submitAnywhere("#checkout-form")
    await page->WeftTesting.waitFor(() => has(page, "#checkout-error"))
    t->expect(text(page, "#checkout-error"))->Expect.toBe("Not enough left of p1-7.")
    t->expect(has(page, "#review-step"))->Expect.toBe(true)
    t->expect(await app()->stock("p19-one"))->Expect.toBe(5)
    t->expect((await app()->session).count)->Expect.toBe(2)
  })
})

describe("the session", () => {
  testAsync("is a cookie the first response sets, which every request after sends", async t => {
    await app()->releaseAll
    let page = app()->open_("/")
    await page->WeftTesting.waitFor(() => has(page, "#blocks-home"))
    let sid = sid(app())
    t->expect(await app()->sessionCount)->Expect.toBe(1)
    let page = app()->open_("/c/shoes")
    await page->WeftTesting.waitFor(() => has(page, "#grid"))
    page->WeftTesting.click("#load-more")
    await page->WeftTesting.waitFor(() => !has(page, "#load-more"))
    t->expect(ShopSupport.sid(app()))->Expect.toBe(sid)
    t->expect(await app()->sessionCount)->Expect.toBe(1)
    // A new visitor.
    app()->WeftTesting.clearCookies
    let page = app()->open_("/")
    await page->WeftTesting.waitFor(() => has(page, "#blocks-home"))
    t->expect(ShopSupport.sid(app()) != sid)->Expect.toBe(true)
    t->expect(await app()->sessionCount)->Expect.toBe(2)
  })

  testAsync("has one even for an RPC that's a visitor's first request", async t => {
    await app()->releaseAll
    let page = app()->open_("/")
    await page->WeftTesting.waitFor(() => has(page, "#blocks-home"))
    await page->WeftTesting.hydrated
    // The cookie's gone (cleared in another tab, say) before the visitor's next request: an RPC.
    app()->WeftTesting.clearCookies
    await change(page, "#currency", "GBP")
    await page->WeftTesting.waitFor(
      () => page->WeftTesting.pageRequests->Array.includes("/_weft/rpc/prefs.setCurrency"),
    )
    await page->WeftTesting.settle
    // The middleware made the RPC a session, which the handler used, and set its cookie.
    t->expect((await app()->session).currency)->Expect.toBe("GBP")
    t->expect(await app()->sessionCount)->Expect.toBe(2)
  })

  testAsync(
    "redirects a signed-out visitor to sign in for their account, then back to it, and out again",
    async t => {
      await app()->releaseAll
      let page = app()->open_("/account")
      await page->WeftTesting.waitFor(() => has(page, "#signin-page"))
      await hydratedAsServed(page)
      t->expect(text(page, "#signin-title"))->Expect.toBe("Sign in")
      // The page is where the redirect led, as the browser's location would be.
      t->expect(page->WeftTesting.url)->Expect.toBe("/signin?next=/account")
      t->expect(await urlOf(page))->Expect.toBe("/signin?next=/account")
      page->WeftTesting.input("#signin-page input", "Grace")
      submitAnywhere("#signin-page form")
      await page->WeftTesting.waitFor(() => has(page, "#account-title"))
      t->expect(text(page, "#account-title"))->Expect.toBe("Grace's account")
      t->expect(text(page, "#account-menu"))->Expect.toBe("Hi, GraceSign out")
      t->expect(has(page, "#no-orders"))->Expect.toBe(true)
      t->expect(await urlOf(page))->Expect.toBe("/account")
      t->expect(addressBar())->Expect.toBe("/account")
      // Signing out, from the header: the refresh is redirected, and the history's entry with it.
      page->WeftTesting.click("#sign-out")
      await page->WeftTesting.waitFor(() => has(page, "#sign-in"))
      t->expect(has(page, "#signin-page"))->Expect.toBe(true)
      t->expect((await app()->session).user)->Expect.toBe("")
      t->expect(await urlOf(page))->Expect.toBe("/signin?next=/account")
      t->expect(addressBar())->Expect.toBe("/signin?next=/account")
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual([
        "/account",
        "/signin?next=/account",
        "/_weft/rpc/auth.signIn",
        "/account",
        "/_weft/rpc/auth.signOut",
        "/account",
        "/signin?next=/account",
      ])
    },
  )

  testAsync(
    "refuses an empty name without asking the server, and a long one on both sides",
    async t => {
      await app()->releaseAll
      let page = app()->open_("/signin?next=/cart")
      await page->WeftTesting.waitFor(() => has(page, "#signin-page"))
      await page->WeftTesting.hydrated
      submitAnywhere("#signin-page form")
      await page->WeftTesting.waitFor(() => has(page, "#signin-page [role=\"alert\"]"))
      t->expect(text(page, "#signin-page [role=\"alert\"]"))->Expect.toBe("Enter a name.")
      page->WeftTesting.input("#signin-page input", "x"->String.repeat(41))
      submitAnywhere("#signin-page form")
      await page->WeftTesting.waitFor(
        () => text(page, "#signin-page [role=\"alert\"]") == "That name is too long.",
      )
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/signin?next=/cart"])
      // A client that doesn't check: the server does.
      app()->WeftTesting.rewriteBodies(
        "/_weft/rpc/auth.signIn",
        _ => JSON.stringify(JSON.String("y"->String.repeat(41))),
      )
      page->WeftTesting.input("#signin-page input", "Grace")
      submitAnywhere("#signin-page form")
      await page->WeftTesting.waitFor(
        () => page->WeftTesting.pageRequests->Array.includes("/_weft/rpc/auth.signIn"),
      )
      await page->WeftTesting.waitFor(
        () => text(page, "#signin-page [role=\"alert\"]") == "That name is too long.",
      )
      app()->WeftTesting.stopRewriting
      t->expect((await app()->session).user)->Expect.toBe("")
      // A good name, on to `next`.
      submitAnywhere("#signin-page form")
      await page->WeftTesting.waitFor(() => has(page, "#cart-title"))
    },
  )
})
