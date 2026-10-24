@@weft.server

/***
Shoppers' sessions: a `sid` cookie (an unguessable id, set by `middleware` on the first response
that lacks one) naming what the server keeps for them: who they've signed in as, their cart, the
currency they picked, what they've looked at, and which half of the home page's experiment they're
in.

Pages get the session from the request context (`get`); RPC handlers, which only see the HTTP
request, from `ofRequest`, which finds the one the middleware made for that very request (so even a
first request's RPC has one) or reads the cookie.
*/

open Types

type t = {
  id: string,
  mutable user: option<string>,
  mutable currency: currency,
  /** SKU and quantity, in the order they were added. */
  mutable cart: array<(string, int)>,
  mutable promo: option<string>,
  /** Goes up with every change to the cart. */
  mutable version: int,
  /** Products looked at, most recent first. */
  mutable viewed: array<string>,
  /** The home page's experiment: `"a"` or `"b"`. */
  mutable bucket: string,
}

let cookieName = "sid"

let sessions: Map.t<string, t> = Map.make()

@val @scope("crypto") external randomUUID: unit => string = "randomUUID"

/** The experiment's half for every new session, if set (the tests'), rather than by the id. */
let fixedBucket: ref<option<string>> = ref(None)

let create = () => {
  let id = randomUUID()
  let session = {
    id,
    user: None,
    currency: USD,
    cart: [],
    promo: None,
    version: 0,
    viewed: [],
    // Half and half, by the id's last hex digit.
    bucket: switch (fixedBucket.contents, id->String.slice(~start=-1)->Int.fromString(~radix=16)) {
    | (Some(bucket), _) => bucket
    | (None, Some(digit)) if mod(digit, 2) == 1 => "b"
    | (None, _) => "a"
    },
  }
  sessions->Map.set(id, session)
  session
}

let key: Servy.Context.Key.t<t> = Servy.Context.Key.make(~name="session")

/** The sessions the middleware made for requests that didn't have one yet. */
let byRequest: WeakMap.t<Request.t, t> = WeakMap.make()

/** The session the request's cookie names, if it's one the server knows. */
let fromCookie = (request: Request.t) =>
  request.headers
  ->Headers.get("cookie")
  ->Null.toOption
  ->Option.flatMap(cookie => Servy.Cookie.parse(cookie)->Map.get(cookieName))
  ->Option.flatMap(id => sessions->Map.get(id))

/** Attaches the session to each request, making one (and setting its cookie) if there's none. */
let middleware: Servy.Middleware.t = next =>
  async ctx =>
    switch fromCookie(ctx.request) {
    | Some(session) => await next(ctx->Servy.RequestContext.set(key, session))
    | None =>
      let session = create()
      byRequest->WeakMap.set(ctx.request, session)->ignore
      let response = await next(ctx->Servy.RequestContext.set(key, session))
      response->Servy.Respond.setCookie(
        cookieName,
        session.id,
        ~options={maxAge: 60 * 60 * 24 * 30},
      )
    }

let get = (ctx: Servy.RequestContext.t) => ctx->Servy.RequestContext.getOrThrow(key)

/** An RPC's session: the one made for this request, or the cookie's. */
let ofRequest = (request: Request.t) =>
  switch byRequest->WeakMap.get(request) {
  | Some(session) => Some(session)
  | None => fromCookie(request)
  }

// The cart

let promos = [("WEFT10", 10, 0), ("LOOM20", 20, 10000)]

/** The cart, priced. */
let cart = (session: t): cart => {
  let lines = session.cart->Array.filterMap(((sku, quantity)) =>
    Db.findSku(sku)->Option.map(((product, variant)) => {
      sku,
      slug: product.summary.slug,
      name: product.summary.name,
      variant: variant.label,
      unitPrice: product.summary.price + variant.priceDelta,
      quantity,
    })
  )
  let subtotal = lines->Array.reduce(0, (total, line) => total + line.unitPrice * line.quantity)
  let percent =
    session.promo
    ->Option.flatMap(code => promos->Array.find(((found, _, _)) => found == code))
    ->Option.mapOr(0, ((_, percent, minimum)) => subtotal >= minimum ? percent : 0)
  {
    lines,
    count: lines->Array.reduce(0, (total, line) => total + line.quantity),
    subtotal,
    discount: subtotal * percent / 100,
    promo: session.promo,
    version: session.version,
  }
}

let changed = session => session.version = session.version + 1

let quantityOf = (session, sku) =>
  session.cart
  ->Array.find(((found, _)) => found == sku)
  ->Option.mapOr(0, ((_, quantity)) => quantity)

/** Sets `sku`'s quantity (0 takes it out). */
let setQuantity = (session, sku, quantity) => {
  session.cart = if quantity <= 0 {
    session.cart->Array.filter(((found, _)) => found != sku)
  } else if session.cart->Array.some(((found, _)) => found == sku) {
    session.cart->Array.map(((found, current)) =>
      found == sku ? (found, quantity) : (found, current)
    )
  } else {
    [...session.cart, (sku, quantity)]
  }
  changed(session)
}

let view = (session, productId) =>
  session.viewed =
    [productId, ...session.viewed->Array.filter(id => id != productId)]->Array.slice(
      ~start=0,
      ~end=6,
    )

let reset = () => sessions->Map.clear
