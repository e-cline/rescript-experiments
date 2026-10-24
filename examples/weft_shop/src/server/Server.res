@@weft.server

/***
The server entry: an `@e-cline/servy` app (the default export), with the session middleware around
everything. Pages answer with `WeftServer.Page.respond` (the HTML for a first request, the bare
payload for the client's), as do the routes of the parts entrypoints fetch again by themselves
(a block, a product's offer, the cart's totals). What the entrypoints change goes through the RPCs in
`Api`, answered at `/_weft/rpc/<id>`.

With `WEFT_SHOP_TEST_ROUTES=1` in the environment, `/test/...` routes let a browser test control
the latency gates, the stock, the layouts and orders.
*/

module App = Servy.App
module RequestContext = Servy.RequestContext
module Respond = Servy.Respond
module Route = Servy.Route
module Query = Servy.Query

@module("virtual:weft/assets") external assets: WeftServer.Page.assets = "default"

external toSignal: 'signal => Latency.signal = "%identity"

/** What the server does with an error a component throws: a line in the log, and no digest. */
let onError = error => {
  Console.error(`weft_shop: a component failed: ${Weft.ErrorBoundary.message(error)}`)
  None
}

/** `response`, with another status. */
let withStatus: (Response.t, int) => Response.t = %raw(`(response, status) =>
  new Response(response.body, {status, headers: response.headers})`)

let requestOf = (ctx: RequestContext.t): Ui.request => {
  session: Session.get(ctx),
  signal: toSignal(ctx.request.signal),
  query: ctx.query->Query.getOr("q", "")->String.trim,
}

let respond = (ctx: RequestContext.t, ~title, element) =>
  WeftServer.Page.respond(ctx.request, element, ~assets, ~title, ~head=Styles.head, ~onError)

let page = (~title, render: (RequestContext.t, Ui.request) => Weft.Element.t): Servy.Handler.t =>
  async ctx => respond(ctx, ~title=`${title} · Loom & Co.`, render(ctx, requestOf(ctx)))

let notFound = ctx =>
  respond(
    ctx,
    ~title="Not found · Loom & Co.",
    <Pages.NotFound request={requestOf(ctx)} />,
  )->withStatus(404)

let param = (ctx, name) => ctx->RequestContext.paramOrThrow(name)

let category = async ctx => {
  let slug = param(ctx, "slug")
  switch Db.categories->Array.find(((found, _)) => found == slug) {
  | Some((_, name)) =>
    await page(~title=name, (ctx, request) =>
      <Pages.CategoryPage slug filters={Pages.filtersOf(ctx.query)} request />
    )(ctx)
  | None => notFound(ctx)
  }
}

/** A product's page, or a part of it, if there's such a product. */
let product = (~title=?, render): Servy.Handler.t =>
  async ctx =>
    switch Db.findBySlug(param(ctx, "slug")) {
    | Some(product) =>
      await page(~title=title->Option.getOr(product.summary.name), (ctx, request) =>
        render(ctx, product, request)
      )(ctx)
    | None => notFound(ctx)
    }

let routes = [
  Route.get(list{}, page(~title="Home", (_, request) => <Pages.HomePage request />)),
  Route.get(list{"c", ":slug"}, category),
  Route.get(list{"search"}, page(~title="Search", (_, request) => <Pages.SearchPage request />)),
  Route.get(
    list{"p", ":slug"},
    product((_, product, request) => {
      Session.view(request.session, product.summary.id)
      <Pages.ProductPage product request />
    }),
  ),
  Route.get(
    list{"p", ":slug", "offer"},
    product((ctx, product, request) =>
      <Pages.OfferPart
        sku={ctx.query
        ->Query.get("sku")
        ->Option.filter(sku => product.variants->Array.some(variant => variant.sku == sku))
        ->Option.getOr((product.variants->Array.getUnsafe(0)).sku)}
        request
      />
    ),
  ),
  Route.get(
    list{"p", ":slug", "also"},
    product((_, product, request) =>
      <Pages.ProductPart part=#also id=product.summary.id request />
    ),
  ),
  Route.get(
    list{"p", ":slug", "questions"},
    product((_, product, request) =>
      <Pages.ProductPart part=#questions id=product.summary.id request />
    ),
  ),
  Route.get(
    list{"blocks", ":page", ":id"},
    page(~title="Block", (ctx, request) =>
      <Pages.BlockPart page={param(ctx, "page")} id={param(ctx, "id")} request />
    ),
  ),
  Route.get(list{"cart"}, page(~title="Cart", (_, request) => <Pages.CartPage request />)),
  Route.get(
    list{"cart", "summary"},
    page(~title="Cart", (_, request) => <Pages.CartSummaryPart request />),
  ),
  // With nothing in the cart, back to it.
  Route.get(list{"checkout"}, async ctx =>
    Session.cart(Session.get(ctx)).lines == []
      ? Respond.redirect("/cart")
      : await page(~title="Checkout", (_, request) => <Pages.CheckoutPage request />)(ctx)
  ),
  Route.get(list{"orders", ":id"}, async ctx =>
    switch Db.findOrder(param(ctx, "id")) {
    | Some(order) =>
      await page(~title=`Order ${order.id}`, (_, request) => <Pages.OrderPage order request />)(ctx)
    | None => notFound(ctx)
    }
  ),
  // Signed out, a redirect to sign in, and back here after (a navigation lands where it leads).
  Route.get(list{"account"}, async ctx =>
    switch Session.get(ctx).user {
    | Some(name) =>
      await page(~title="Account", (_, request) => <Pages.AccountPage name request />)(ctx)
    | None => Respond.redirect("/signin?next=/account")
    }
  ),
  Route.get(
    list{"signin"},
    page(~title="Sign in", (ctx, request) =>
      <Pages.SignInPage
        // Only a path on this site.
        next={ctx.query
        ->Query.get("next")
        ->Option.filter(next => next->String.startsWith("/") && !(next->String.startsWith("//")))
        ->Option.getOr("/")}
        request
      />
    ),
  ),
  // The RPCs (`Api`'s, answered by `ApiServer`'s handlers).
  Route.post(list{"_weft", "rpc", ":id"}, async ctx =>
    await ApiServer.router->WeftServer.RpcServer.respond(ctx.request, ~id=param(ctx, "id"))
  ),
]

@val @scope(("process", "env"))
external testRoutesFlag: Nullable.t<string> = "WEFT_SHOP_TEST_ROUTES"

/** For the browser tests: the server's state, controlled over HTTP. */
let testRoutes = [
  // What the browser tests wait for before they start (a page would wait on the gates).
  Route.get(list{"test", "ready"}, async _ => Respond.text("ready")),
  Route.post(list{"test", "reset"}, async _ => {
    Control.reset()
    Respond.empty()
  }),
  Route.post(list{"test", "release", ":gate"}, async ctx => {
    Latency.release(param(ctx, "gate"))
    Respond.empty()
  }),
  Route.post(list{"test", "release-prefix", ":prefix"}, async ctx => {
    Latency.releasePrefix(param(ctx, "prefix"))
    Respond.empty()
  }),
  Route.post(list{"test", "release-all"}, async _ => {
    Latency.releasePrefix("")
    Respond.empty()
  }),
  Route.post(list{"test", "fail", ":gate"}, async ctx => {
    Latency.fail(param(ctx, "gate"), "the service is down")
    Respond.empty()
  }),
  Route.post(list{"test", "hold", ":gate"}, async ctx => {
    Latency.hold(param(ctx, "gate"))
    Respond.empty()
  }),
  Route.post(list{"test", "heal", ":gate"}, async ctx => {
    Latency.heal(param(ctx, "gate"))
    Respond.empty()
  }),
  Route.post(list{"test", "stock", ":sku", ":count"}, async ctx => {
    Db.setStock(param(ctx, "sku"), param(ctx, "count")->Int.fromString->Option.getOr(0))
    Respond.empty()
  }),
  Route.post(list{"test", "advance", ":order"}, async ctx => {
    Db.advanceOrder(param(ctx, "order"))
    Respond.empty()
  }),
  Route.post(list{"test", "poll", ":ms"}, async ctx => {
    Pages.pollEvery := param(ctx, "ms")->Int.fromString->Option.filter(ms => ms > 0)
    Respond.empty()
  }),
  Route.post(list{"test", "move", ":page", ":id", ":index"}, async ctx => {
    Cms.move(
      param(ctx, "page"),
      param(ctx, "id"),
      param(ctx, "index")->Int.fromString->Option.getOr(0),
    )
    Respond.empty()
  }),
]

let app =
  App.build()
  ->App.use(Session.middleware)
  ->App.router(testRoutesFlag->Nullable.toOption == Some("1") ? [...routes, ...testRoutes] : routes)

let default = app
