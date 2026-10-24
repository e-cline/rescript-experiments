@@weft.server

/***
The handlers of the RPCs `Api` declares, and the router that answers them (mounted in `Server`).
Each finds the shopper's session from the HTTP request (`Session.ofRequest`): the RPCs are public
endpoints, so who's asking is the handler's to check.
*/

module RpcServer = WeftServer.RpcServer

open Types

external toSignal: 'signal => Latency.signal = "%identity"

let withSession = async (http: Request.t, f) =>
  switch Session.ofRequest(http) {
  | Some(session) => await f(session)
  | None => Error(Api.NoSession)
  }

let addToCart = RpcServer.handler(Api.addToCart, async ({sku, quantity}, ~http) =>
  await withSession(http, async session =>
    switch Db.findSku(sku) {
    | None => Error(Api.NoSuchProduct)
    | Some(_) =>
      let wanted = Session.quantityOf(session, sku) + quantity
      if wanted > Db.stockOf(sku) {
        Error(Api.OutOfStock([sku]))
      } else if wanted > 10 {
        Error(Api.BadQuantity)
      } else {
        Session.setQuantity(session, sku, wanted)
        Ok(Session.cart(session))
      }
    }
  )
)

let setQuantity = RpcServer.handler(Api.setQuantity, async ({sku, quantity}, ~http) =>
  await withSession(http, async session =>
    if quantity > Db.stockOf(sku) {
      Error(Api.OutOfStock([sku]))
    } else {
      Session.setQuantity(session, sku, quantity)
      Ok(Session.cart(session))
    }
  )
)

let applyPromo = RpcServer.handler(Api.applyPromo, async (code, ~http) =>
  await withSession(http, async session =>
    if code == "SUMMER" {
      Error(Api.ExpiredPromo)
    } else if Session.promos->Array.some(((found, _, _)) => found == code) {
      session.promo = Some(code)
      Session.changed(session)
      Ok(Session.cart(session))
    } else {
      Error(Api.UnknownPromo)
    }
  )
)

let setCurrency = RpcServer.handler(Api.setCurrency, async (currency, ~http) =>
  await withSession(http, async session => {
    session.currency = currency
    Ok()
  })
)

let signIn = RpcServer.handler(Api.signIn, async (name, ~http) =>
  await withSession(http, async session => {
    session.user = Some(Db.user(name).name)
    Ok(name)
  })
)

let signOut = RpcServer.handler(Api.signOut, async ((), ~http) =>
  await withSession(http, async session => {
    session.user = None
    Ok()
  })
)

let toggleWishlist = RpcServer.handler(Api.toggleWishlist, async (productId, ~http) =>
  await withSession(http, async session =>
    switch (session.user, Db.find(productId)) {
    | (None, _) => Error(Api.NotSignedIn)
    | (_, None) => Error(Api.NoSuchProduct)
    | (Some(name), Some(_)) =>
      let wishlist = Db.user(name).wishlist
      if wishlist->Set.has(productId) {
        wishlist->Set.delete(productId)->ignore
        Ok(false)
      } else {
        wishlist->Set.add(productId)
        Ok(true)
      }
    }
  )
)

let suggest = RpcServer.handler(Api.suggest, async (query, ~http) => {
  await Latency.wait("search:suggest", ~signal=toSignal(http.signal))
  Ok(
    Db.search(query)
    ->Array.slice(~start=0, ~end=5)
    ->Array.map(summary => {slug: summary.slug, name: summary.name, category: summary.category}),
  )
})

let more = RpcServer.handler(Api.more, async ({category, query, page}, ~http) =>
  await withSession(http, async session => {
    let params = Servy.Query.fromString(query)
    let search = params->Servy.Query.getOr("q", "")
    let request: Ui.request = {session, signal: toSignal(http.signal), query: search}
    let items = category == "" ? Db.search(search) : Db.query(category, Pages.filtersOf(params))
    let (items, next) = Pages.pageOf(items, page)
    Ok({Api.items: Ui.gridItems(items, request), next})
  })
)

let subscribers: Set.t<string> = Set.make()

let subscribe = RpcServer.handler(Api.subscribe, async (email, ~http as _) => {
  subscribers->Set.add(email)
  Ok()
})

let placeOrder = RpcServer.handler(Api.placeOrder, async (details, ~http) =>
  await withSession(http, async session => {
    let cart = Session.cart(session)
    if cart.lines == [] {
      Error(Api.EmptyCart)
    } else {
      switch Db.placeOrder(
        cart.lines,
        ~name=details.name,
        ~total=cart.subtotal - cart.discount + deliveryCost(details.delivery),
        ~manualStatus=Latency.mode.contents == Manual,
      ) {
      | Ok(id) =>
        session.cart = []
        session.promo = None
        Session.changed(session)
        // An order placed while signed in is the user's; a guest's is under the name they gave.
        session.user->Option.forEach(
          name =>
            if name != details.name {
              Db.user(name).orders->Array.push(id)
            },
        )
        Ok(id)
      | Error(skus) => Error(Api.OutOfStock(skus))
      }
    }
  })
)

/** What `/_weft/rpc/<id>` answers: these RPCs, and no others. */
let router = RpcServer.router(
  [
    addToCart,
    setQuantity,
    applyPromo,
    setCurrency,
    signIn,
    signOut,
    toggleWishlist,
    suggest,
    more,
    subscribe,
    placeOrder,
  ],
  ~onError=error => {
    Console.error(`weft_shop: an RPC failed: ${Weft.ErrorBoundary.message(error)}`)
    None
  },
)
