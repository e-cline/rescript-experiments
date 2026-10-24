@@weft.server

/***
The pages, and the parts of them their entrypoints fetch again by themselves. Every slow query waits
on `Latency` under a `Suspense` boundary, so the shell (the header, and whatever's ready) comes
first and the rest streams in, and every query is given the request's signal, so one still waiting
when the shopper navigates away stops.
*/

open Types
open Ui

let viewerOf = (request: request): Cms.viewer => {
  user: request.session.user,
  bucket: request.session.bucket,
}

module Breadcrumbs = {
  @weft.component({kind: Server})
  let make = (~trail: array<(string, string)>, ~current: string) =>
    <nav className="breadcrumbs" ariaLabel="Breadcrumbs">
      <Link href="/"> {text("Home")} </Link>
      {trail
      ->Array.map(((label, href)) =>
        <WeftDom.Jsx.Fragment key=href>
          {text(" / ")}
          <Link href> {text(label)} </Link>
        </WeftDom.Jsx.Fragment>
      )
      ->WeftDom.Jsx.array}
      {text(" / ")}
      <span ariaCurrent="page"> {text(current)} </span>
    </nav>
}

// Server-driven pages

module PageBlocks = {
  /** A page's blocks, once the CMS has said what they are. */
  @weft.component({kind: Server})
  let make = async (~page: string, ~request: request) => {
    await Latency.wait(`layout:${page}`, ~signal=request.signal)
    <div className="blocks" id={`blocks-${page}`}>
      {Blocks.blockList(Cms.layout(page, viewerOf(request)), ~page, ~request)}
    </div>
  }
}

module HomePage = {
  @weft.component({kind: Server})
  let make = (~request: request) =>
    <Shell request>
      <Weft.Suspense fallback={loading("home-loading", "Loading the store…")}>
        <PageBlocks page="home" request />
      </Weft.Suspense>
    </Shell>
}

module BlockPart = {
  /** One block, by itself: what its frame fetches again. */
  @weft.component({kind: Server})
  let make = (~page: string, ~id: string, ~request: request) =>
    switch Cms.find(Cms.layout(page, viewerOf(request)), id) {
    | Some(block) => <Blocks.Content block request />
    | None => <p className="gone"> {text("This isn't here any more.")} </p>
    }
}

// The catalog

let pageSize = 4

/** A category page's filters, from its query string. */
let filtersOf = (query: Servy.Query.t): Db.filters => {
  colors: query
  ->Servy.Query.getAll("color")
  ->Array.filter(color => Db.colors->Array.includes(color)),
  low: query->Servy.Query.getInt("min"),
  high: query->Servy.Query.getInt("max"),
  inStock: query->Servy.Query.get("instock") == Some("1"),
  sort: Db.sortOf(query->Servy.Query.get("sort")),
}

/** The filters as a query string, always written the same way (the grid is keyed by it). */
let queryOf = (filters: Db.filters) => {
  let pairs = [
    ...filters.colors->Array.toSorted(String.compare)->Array.map(color => ("color", color)),
    ...filters.low->Option.mapOr([], low => [("min", Int.toString(low))]),
    ...filters.high->Option.mapOr([], high => [("max", Int.toString(high))]),
    ...filters.inStock ? [("instock", "1")] : [],
    ...filters.sort == Featured ? [] : [("sort", Db.sortValue(filters.sort))],
  ]
  Servy.Query.fromPairs(pairs)->Servy.Query.toString
}

/** A page of `items` (from 1), and the next page's number, if there's one. */
let pageOf = (items: array<summary>, page) => {
  let start = (page - 1) * pageSize
  (
    items->Array.slice(~start, ~end=start + pageSize),
    start + pageSize < Array.length(items) ? Some(page + 1) : None,
  )
}

module Facets = {
  @weft.component({kind: Server})
  let make = async (~slug, ~filters: Db.filters, ~request: request) => {
    await Latency.wait(`facets:${slug}`, ~signal=request.signal)
    <FacetPanel
      basePath={`/c/${slug}`}
      query={queryOf(filters)}
      facets={Db.facets(slug, filters)}
      sort={Db.sortValue(filters.sort)}
    />
  }
}

module Results = {
  @weft.component({kind: Server})
  let make = async (~slug, ~filters: Db.filters, ~request: request) => {
    await Latency.wait(`results:${slug}`, ~signal=request.signal)
    let items = Db.query(slug, filters)
    let (first, next) = pageOf(items, 1)
    let query = queryOf(filters)
    <ProductGrid
      key={`${slug}?${query}`}
      items={gridItems(first, request)}
      total={Array.length(items)}
      next
      category=slug
      query
    />
  }
}

module CategoryPage = {
  @weft.component({kind: Server})
  let make = (~slug, ~filters: Db.filters, ~request: request) =>
    <Shell request>
      <Breadcrumbs trail=[] current={Db.categoryName(slug)} />
      <Weft.Suspense fallback={loading("banner-loading", "…")}>
        <PageBlocks page={`c-${slug}`} request />
      </Weft.Suspense>
      <div className="catalog">
        <Weft.Suspense fallback={loading("facets-loading", "Loading filters…")}>
          <Facets slug filters request />
        </Weft.Suspense>
        <Weft.Suspense fallback={loading("results-loading", "Finding products…")}>
          <Results slug filters request />
        </Weft.Suspense>
      </div>
    </Shell>
}

module SearchResults = {
  @weft.component({kind: Server})
  let make = async (~request: request) => {
    await Latency.wait("results:search", ~signal=request.signal)
    let items = Db.search(request.query)
    let (first, next) = pageOf(items, 1)
    let query = Servy.Query.fromPairs([("q", request.query)])->Servy.Query.toString
    <ProductGrid
      key=query items={gridItems(first, request)} total={Array.length(items)} next category="" query
    />
  }
}

module SearchPage = {
  @weft.component({kind: Server})
  let make = (~request: request) =>
    <Shell request>
      <h1 id="search-title"> {text(`Results for “${request.query}”`)} </h1>
      <Weft.Suspense fallback={loading("results-loading", "Searching…")}>
        <SearchResults request />
      </Weft.Suspense>
    </Shell>
}

// A product

module Offer = {
  /** The picked variant's price and stock, and the add to cart button: what `ProductOffer` refetches. */
  @weft.component({kind: Server})
  let make = async (~sku, ~request: request) => {
    await Latency.wait(`offer:${sku}`, ~signal=request.signal)
    switch Db.findSku(sku) {
    | Some((product, variant)) =>
      let stock = Db.stockOf(sku)
      let price = product.summary.price + variant.priceDelta
      <>
        <Price
          id="offer-price"
          cents=price
          compareAt=?{product.summary.compareAt->Option.map(was => was + variant.priceDelta)}
        />
        <p id="stock" className={stock == 0 ? "stock out" : "stock"}>
          {text(
            switch stock {
            | 0 => `${variant.label}: sold out`
            | 1 => `${variant.label}: only 1 left`
            | stock => `${variant.label}: ${Int.toString(stock)} in stock`
            },
          )}
        </p>
        <AddToCart sku name=product.summary.name stock />
      </>
    | None => <p id="stock"> {text("Not sold any more.")} </p>
    }
  }
}

module OfferPart = {
  @weft.component({kind: Server})
  let make = (~sku, ~request) =>
    <Weft.Suspense fallback={loading("offer-loading", "Checking stock…")}>
      <Offer sku request />
    </Weft.Suspense>
}

module AlsoBought = {
  @weft.component({kind: Server})
  let make = async (~id, ~request: request) => {
    await Latency.wait(`rail:also-${id}`, ~signal=request.signal)
    let items = Db.alsoBought(id)
    <Carousel id="also-bought" title="Bought together" count={Array.length(items)}>
      {cards(items, request)}
    </Carousel>
  }
}

module Questions = {
  /** From the questions service, which fails now and then. */
  @weft.component({kind: Server})
  let make = async (~id, ~request: request) => {
    await Latency.wait(`qa:${id}`, ~signal=request.signal)
    let name = Db.summary(id)->Option.mapOr("it", summary => summary.name)
    <div id="questions">
      <h2> {text("Questions")} </h2>
      <dl>
        <dt> {text(`Is the ${name} true to size?`)} </dt>
        <dd> {text("Yes: most shoppers take their usual size.")} </dd>
        <dt> {text("Can I return it?")} </dt>
        <dd> {text("Within 30 days, unworn.")} </dd>
      </dl>
    </div>
  }
}

/** A part of a product page that's fetched again by itself, in its boundary. */
module ProductPart = {
  @weft.component({kind: Server})
  let make = (~part, ~id, ~request) =>
    switch part {
    | #also =>
      <Weft.Suspense fallback={loading("also-loading", "Loading…")}>
        <AlsoBought id request />
      </Weft.Suspense>
    | #questions =>
      <Weft.Suspense fallback={loading("questions-loading", "Loading questions…")}>
        <Questions id request />
      </Weft.Suspense>
    }
}

module ProductPage = {
  @weft.component({kind: Server})
  let make = (~product: product, ~request: request) => {
    let {summary} = product
    let firstSku =
      product.variants
      ->Array.find(variant => Db.stockOf(variant.sku) > 0)
      ->Option.getOr(product.variants->Array.getUnsafe(0))
    <Shell request>
      <Breadcrumbs
        trail=[(Db.categoryName(summary.category), `/c/${summary.category}`)] current=summary.name
      />
      <div className="product" id={`product-${summary.id}`}>
        <Gallery name=summary.name hue=summary.hue />
        <div className="product-info">
          <h1 id="product-name"> {text(summary.name)} </h1>
          <WishlistButton productId=summary.id saved={wishlist(request)->Set.has(summary.id)} />
          <p id="rating"> {text(`★ ${Float.toFixed(summary.rating, ~digits=1)}`)} </p>
          <ProductOffer slug=summary.slug variants=product.variants selected=firstSku.sku>
            <OfferPart sku=firstSku.sku request />
          </ProductOffer>
          <p id="description"> {text(product.description)} </p>
        </div>
      </div>
      <section id="reviews-section">
        <h2> {text("Reviews")} </h2>
        <ReviewList
          reviews={Latency.after(`reviews:${summary.id}`, ~signal=request.signal, () =>
            Db.reviewsOf(summary.id)
          )}
        />
      </section>
      <BlockFrame id="also" src={`/p/${summary.slug}/also`}>
        <ProductPart part=#also id=summary.id request />
      </BlockFrame>
      <BlockFrame id="questions" src={`/p/${summary.slug}/questions`}>
        <ProductPart part=#questions id=summary.id request />
      </BlockFrame>
    </Shell>
  }
}

// The cart, checkout and orders

module CartSummary = {
  /** The totals, worked out on the server: what `CartSummaryFrame` refetches. */
  @weft.component({kind: Server})
  let make = async (~request: request) => {
    await Latency.wait("block:summary", ~signal=request.signal)
    let cart = Session.cart(request.session)
    let total = cart.subtotal - cart.discount
    <dl id="summary">
      <dt> {text("Subtotal")} </dt>
      <dd>
        <Price id="summary-subtotal" cents=cart.subtotal />
      </dd>
      {cart.discount > 0
        ? <>
            <dt> {text(`Discount (${cart.promo->Option.getOr("")})`)} </dt>
            <dd>
              <Price id="summary-discount" cents={-cart.discount} />
            </dd>
          </>
        : WeftDom.Jsx.null}
      <dt> {text("Total")} </dt>
      <dd>
        <Price id="summary-total" cents=total />
      </dd>
      <dt> {text("Points")} </dt>
      <dd id="summary-points"> {text(Int.toString(total / 100))} </dd>
    </dl>
  }
}

module CartSummaryPart = {
  @weft.component({kind: Server})
  let make = (~request) =>
    <Weft.Suspense fallback={loading("summary-loading", "Adding it up…")}>
      <CartSummary request />
    </Weft.Suspense>
}

module CartPage = {
  @weft.component({kind: Server})
  let make = (~request: request) =>
    <Shell request>
      <h1 id="cart-title"> {text("Your cart")} </h1>
      <div className="cart">
        <CartLines />
        <aside className="cart-side">
          <CartSummaryFrame>
            <CartSummaryPart request />
          </CartSummaryFrame>
          <PromoForm applied=request.session.promo />
          <Link id="checkout-link" className="cta" href="/checkout"> {text("Check out")} </Link>
        </aside>
      </div>
    </Shell>
}

module CheckoutPage = {
  @weft.component({kind: Server})
  let make = (~request: request) => {
    let cart = Session.cart(request.session)
    <Shell request>
      <h1 id="checkout-title"> {text("Checkout")} </h1>
      // An empty cart is redirected to the cart (`Server`), so there's something to check out.
      <CheckoutForm total={cart.subtotal - cart.discount} count=cart.count />
    </Shell>
  }
}

module DeliveryEstimate = {
  @weft.component({kind: Server})
  let make = async (~order: order, ~request: request) => {
    await Latency.wait(`estimate:${order.id}`, ~signal=request.signal)
    <p id="estimate">
      {text(
        switch order.status {
        | Delivered => "Delivered."
        | Shipped => "Arriving tomorrow."
        | Placed | Packed => "Arriving in 3–5 days."
        },
      )}
    </p>
  }
}

/** How often the order page refreshes itself, in milliseconds (`None`: never). */
let pollEvery: ref<option<int>> = ref(Some(3000))

module OrderPage = {
  @weft.component({kind: Server})
  let make = (~order: order, ~request: request) =>
    <Shell request>
      <h1 id="order-title"> {text(`Order ${order.id}`)} </h1>
      <p id="order-status"> {text(`Status: ${statusLabel(order.status)}`)} </p>
      <OrderTracker status=order.status every=?pollEvery.contents />
      <ul id="order-lines">
        {order.lines
        ->Array.map(line =>
          <li key=line.sku>
            {text(`${line.name} (${line.variant}) × ${Int.toString(line.quantity)}`)}
          </li>
        )
        ->WeftDom.Jsx.array}
      </ul>
      <p>
        {text("Total: ")}
        <Price id="order-total" cents=order.total />
      </p>
      <Weft.Suspense fallback={loading("estimate-loading", "Estimating delivery…")}>
        <DeliveryEstimate order request />
      </Weft.Suspense>
    </Shell>
}

module AccountPage = {
  @weft.component({kind: Server})
  let make = (~name: string, ~request: request) => {
    let user = Db.user(name)
    let saved = user.wishlist->Set.values->Iterator.toArray->Array.filterMap(Db.summary)
    <Shell request>
      <h1 id="account-title"> {text(`${name}'s account`)} </h1>
      <section id="orders">
        <h2> {text("Orders")} </h2>
        {user.orders == []
          ? <p id="no-orders"> {text("No orders yet.")} </p>
          : <ul>
              {user.orders
              ->Array.map(id =>
                <li key=id>
                  <Link id={`order-link-${id}`} href={`/orders/${id}`}> {text(id)} </Link>
                </li>
              )
              ->WeftDom.Jsx.array}
            </ul>}
      </section>
      <section id="wishlist">
        <h2> {text("Saved for later")} </h2>
        {saved == []
          ? <p id="no-saved"> {text("Nothing saved yet.")} </p>
          : <div className="card-row"> {cards(saved, request)} </div>}
      </section>
    </Shell>
  }
}

module SignInPage = {
  @weft.component({kind: Server})
  let make = (~next: string, ~request: request) =>
    <Shell request>
      <h1 id="signin-title"> {text("Sign in")} </h1>
      <SignInForm next />
    </Shell>
}

module NotFound = {
  @weft.component({kind: Server})
  let make = (~request: request) =>
    <Shell request>
      <h1 id="not-found"> {text("Not found")} </h1>
      <Link href="/"> {text("Back to the store")} </Link>
    </Shell>
}
