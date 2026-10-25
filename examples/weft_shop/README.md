# weft_shop

A storefront, "Loom & Co.", built with [Weft's server components](../../packages/weft_server): the
largest of the examples, and a test bed for how Weft's features work together, with the latency of
real services in between. Its home and category pages are server-driven: what they're made of is
data the server decides on for each request, and each part of them streams in by itself.

- **Server-driven pages** ([`src/server/Cms.res`](src/server/Cms.res),
  [`src/server/Blocks.res`](src/server/Blocks.res)): the home page and each category's banner are a
  tree of blocks (heroes, rails of products, promotions, tabs, columns, live deals, an experiment)
  kept as data and changed at runtime, and personalised: signed-in shoppers are welcomed, get
  recommendations and a rail to buy again, and each half of the experiment sees its own promotion.
  Every block is a server component waiting on its own service, in a `Suspense` boundary of its own,
  inside a `BlockFrame` entrypoint: an error boundary (a block that fails says so, with Retry) that
  fetches the block again from its own route (`useRefetchable`), on Retry or, for live deals, every
  few seconds. Containers render their blocks the same way, so a rail in a tab streams, fails and
  refetches by itself too, and blocks keep their state when a refresh brings a layout that moved
  them.
- **Streaming everywhere**: the shell first, then the layout, then each block, then each card's
  stock, each under its own boundary; a product's offer, reviews (a promise, read on the client with
  `Hooks.use`), rails and questions; an order's delivery estimate.
- **The catalog** ([`src/server/Pages.res`](src/server/Pages.res)): filters the server decides on
  per category (`FacetPanel`), each change a navigation to the page's new URL (showing what was
  picked until it's rendered), with the results in a grid (`ProductGrid`) keyed by the filters, a
  quick filter over the cards already there (`useDeferredValue`), and "Load more" from the
  `catalog.more` RPC, whose answer is the cards themselves, rendered on the server, their stock
  still streaming.
- **Search**: suggestions as you type (`search.suggest`, through `Rpc.call` with an `AbortSignal`,
  so each query cancels the one before it), results on Enter, and the box in the header keeping what
  was typed as the shopper navigates.
- **A product's page**: variants whose offer (price, stock, the add to cart button) is fetched again
  by itself (`ProductOffer`), keeping the quantity chosen; a gallery; reviews sorted in a
  transition.
- **The cart, client and server** ([`src/client/Store.res`](src/client/Store.res),
  [`src/client/ShopContext.res`](src/client/ShopContext.res)): the cart an RPC answers with goes to
  a `signals` atom, which `ShopShell` (the entrypoint around every page, providing the page's
  context) reads and hands down, newest of its and the server's, so the header's count, the drawer
  (a portal) and the cart page follow at once; the cart page's quantities change before the server
  answers (a reducer), and its totals, rendered on the server, are fetched again whenever the cart's
  version goes up.
- **Context and currency**: every price is a `Price` entrypoint reading the currency from
  `ShopContext`, so picking one re-renders every price on the page with nothing fetched, and the
  `prefs.setCurrency` RPC makes it the session's, for the next pages the server renders.
- **Sessions and auth** ([`src/server/Session.res`](src/server/Session.res)): an `sid` cookie that
  `@e-cline/servy` middleware sets on the first response without one, naming what the server keeps
  for the shopper; signing in (a name, no password: a demo) from a dialog rendered into `<body>` (a
  portal) that takes the focus (`autoFocus`), or from the sign-in page the account page redirects a
  signed-out shopper to (a navigation lands at the URL a redirect leads to); RPC handlers finding
  the session from the HTTP request, even on a visitor's first request.
- **Checkout**: a three-step form (a reducer, labels linked by `useId`; an empty cart is redirected
  back to the cart), the address checked as the RPC will check it before moving on, and the order
  refused, saying which item, if someone else bought the last of it first. The order's page
  refreshes itself until it's delivered.
- **RPCs** ([`src/shared/Api.res`](src/shared/Api.res), handled in
  [`src/server/ApiServer.res`](src/server/ApiServer.res)): eleven, with object, variant, option and
  custom codecs, `prepare` steps that send nothing for an empty promo code or name, `check`s on both
  sides, and errors the shopper is told about.
- **Styles** ([`weft_css`](../../packages/weft_css)): each component's beside it (the theme's
  colours, as CSS variables, and the page's own rules in
  [`src/shared/Theme.res`](src/shared/Theme.res)), and no other class names. The tests find elements
  by role, ARIA attribute or `data-id` (`dataId`): an element has an `id` only when the page needs
  it (a label's, an ARIA reference's). Each page is sent the stylesheets of what it renders: the
  shell's linked in its head, a block's with it as it streams in (its swap waiting for them), a page
  navigated to with its payload (shown once they've loaded). Server components' styles (the frame,
  the blocks, the pages) never reach the client as code, only as CSS. What changes at run time (a
  product's hue, a carousel's page) is a CSS variable its class uses, set with `Css.vars`.
- **The rest**: an offline banner (`useSyncExternalStore` with a server snapshot), a countdown that
  renders the server's time first so hydration matches, and toasts.

The "database" ([`src/server/Db.res`](src/server/Db.res)) is in memory and the same every time.
Every slow call waits on [`src/server/Latency.res`](src/server/Latency.res): in `vp dev` and
`vp run start`, a random time from a seeded generator, with the recommendations and questions
services failing now and then; in the tests, nothing opens until the test says. `WEFT_SHOP_LATENCY`
(`random`, `fixed`, `off` or `manual`), `WEFT_SHOP_SEED` and `WEFT_SHOP_FAIL_RATE` set it.

Run it:

```bash
pnpm --filter @e-cline/weft_shop_example exec vp run dev
```

or build it and serve the build:

```bash
pnpm --filter @e-cline/weft_shop_example exec vp run start
```

## Tests

[`tests/`](tests) runs the app's scenarios through
[the plugin's harness](../../tools/weft_vite_plugin#testing-an-app): the server in a worker thread
(with its controls, [`tests/ShopControl.res`](tests/ShopControl.res), called there), each page in
jsdom, cookies kept as a browser keeps them. Each test starts with every latency gate closed, and
opens them in the order it's about:

- [`Home_test.res`](tests/Home_test.res): the home page streaming block by block in any order, and
  in chunks of any size; a boundary whose content arrives while an entrypoint's chunk is still
  loading hydrated once it has, with nothing rendered twice; navigating away from a page still
  streaming, which stops its services; blocks working once hydrated; a refresh bringing a layout
  with blocks moved, added and removed, each keeping its state; the experiment; a block that fails,
  and Retry; live deals refetching themselves; personalisation after signing in, and recommendations
  failing; the currency changing every price at once; a page closed when the next opens.
- [`Catalog_test.res`](tests/Catalog_test.res): a category page's blocks, filters and results
  streaming by themselves; "Load more" (server-rendered cards from the RPC, their stock streaming
  after); the quick filter, with nothing fetched; filters and sort as navigations, the grid starting
  afresh, the results staying until the new ones are ready, the range reset when the filters are
  cleared; search suggestions, a newer query cancelling an older one's request; search results.
- [`Product_test.res`](tests/Product_test.res): the offer, reviews, rail and questions streaming by
  themselves; hydration in chunks of any size; another variant's offer fetched by itself, keeping
  the quantity (clamped to the stock); adding to the cart, refused past the stock; the drawer; a
  sold out variant; reviews sorted in a transition; the questions failing, and Retry; the wishlist,
  signed out and in, and put back when the server says no.
- [`Cart_test.res`](tests/Cart_test.res): the cart's lines and server-rendered totals; quantities
  changed at once, the totals following by themselves; promo codes (an empty one never sent, unknown
  and expired ones refused); checking out, the address checked on the client, the order placed, and
  its page refreshing itself until it's delivered; an item that ran out first; the session's cookie,
  even for an RPC that's a visitor's first request; the account page redirecting to sign in, and
  back after, and out again; an empty cart's checkout redirecting to the cart; names refused on both
  sides.
- [`Styles_test.res`](tests/Styles_test.res): each page's stylesheets (the home page's head linking
  only what it renders, the cart's sent when it's opened), nothing shown without its CSS as the page
  streams or the shopper navigates, and the old page kept while the new one's sheets load.

[`e2e/`](e2e) checks, in Chromium against the build, what only a browser can, served twice:

- [`shop.e2e.ts`](e2e/shop.e2e.ts), with the latency gated (`WEFT_SHOP_TEST_ROUTES=1` adds routes
  that open the gates): the home page streaming; blocks arriving while a chunk is held back,
  hydrated once it's loaded, not rendered twice; a whole purchase, filter to order; the sign-in
  dialog's focus and Escape; links to pages that redirect, landing at the redirect's URL; the
  currency kept across a reload; the back and forward buttons through filtered pages; a failed block
  retried; and the pages readable with JavaScript off.
- [`styles.e2e.ts`](e2e/styles.e2e.ts), gated too, with every stylesheet slowed down: a probe on
  every frame finds nothing shown without its CSS, from the home page streaming to a navigation, a
  product, the cart's drawer and page, and a quantity changed (its totals refetched); and, as a
  control, that it does find a page shown before its stylesheet. In Firefox and WebKit too.
- [`random.e2e.ts`](e2e/random.e2e.ts), with seeded random latency and failures, as `vp run start`
  serves it: every page streaming in completely, once, and hydrating; navigating quickly through
  pages still streaming; and a purchase, retrying whatever fails.

Each with nothing in the console. Run them (they need Chromium:
`pnpm --filter @e-cline/weft_shop_example exec playwright install chromium`):

```bash
pnpm --filter @e-cline/weft_shop_example exec vp run e2e
```
