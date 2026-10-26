@@weft.server

/***
The pages, and the parts of them their entrypoints fetch again by themselves. Every slow query waits
on `Latency` under a `Suspense` boundary, so the shell (the header, and whatever's ready) comes
first and the rest streams in, and every query is given the request's signal, so one still waiting
when the shopper navigates away stops.
*/

open Types
open Ui
open WeftCss

module Ui = WeftUi

module Styles = {
  let breadcrumbs = Css.class({marginBottom: Px(12)})
  let catalog = Css.class({marginTop: Px(16)})
}

let viewerOf = (request: request): Cms.viewer => {
  user: request.session.user,
  bucket: request.session.bucket,
}

module Breadcrumbs = {
  @weft.component({kind: Server})
  let make = (~trail: array<(string, string)>, ~current: string) =>
    <Ui.Breadcrumbs.Root className=Styles.breadcrumbs>
      <Ui.Breadcrumbs.Item>
        <Link href="/"> {text("Home")} </Link>
      </Ui.Breadcrumbs.Item>
      {trail
      ->Array.map(((label, href)) =>
        <Ui.Breadcrumbs.Item key=href>
          <Link href> {text(label)} </Link>
        </Ui.Breadcrumbs.Item>
      )
      ->WeftDom.Jsx.array}
      <Ui.Breadcrumbs.Current> {text(current)} </Ui.Breadcrumbs.Current>
    </Ui.Breadcrumbs.Root>
}

// Server-driven pages

module PageBlocks = {
  /** A page's blocks, once the CMS has said what they are. */
  @weft.component({kind: Server})
  let make = async (~page: string, ~request: request) => {
    await Latency.wait(`layout:${page}`, ~signal=request.signal)
    <div dataId={`blocks-${page}`}>
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
    | None => <p> {text("This isn't here any more.")} </p>
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
      <Ui.Grid template="220px minmax(0, 1fr)" gap=#xl stackBelow=#md className=Styles.catalog>
        <Weft.Suspense fallback={loading("facets-loading", "Loading filters…")}>
          <Facets slug filters request />
        </Weft.Suspense>
        <Weft.Suspense fallback={loading("results-loading", "Finding products…")}>
          <Results slug filters request />
        </Weft.Suspense>
      </Ui.Grid>
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
      <Ui.Heading level=#h1 dataId="search-title">
        {text(`Results for “${request.query}”`)}
      </Ui.Heading>
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
          dataId="offer-price"
          cents=price
          compareAt=?{product.summary.compareAt->Option.map(was => was + variant.priceDelta)}
        />
        <Ui.Text dataId="stock" tone={stock == 0 ? #danger : #success} size=#sm>
          {text(
            switch stock {
            | 0 => `${variant.label}: sold out`
            | 1 => `${variant.label}: only 1 left`
            | stock => `${variant.label}: ${Int.toString(stock)} in stock`
            },
          )}
        </Ui.Text>
        <AddToCart sku name=product.summary.name stock />
      </>
    | None => <Ui.Text dataId="stock" tone=#muted> {text("Not sold any more.")} </Ui.Text>
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
    <Ui.Stack gap=#sm dataId="questions">
      <Ui.Heading level=#h2 size=#lg> {text("Questions")} </Ui.Heading>
      <Ui.Accordion.Root>
        {[
          (`Is the ${name} true to size?`, "Yes: most shoppers take their usual size."),
          ("Can I return it?", "Within 30 days, unworn."),
        ]
        ->Array.map(((question, answer)) =>
          <Ui.Accordion.Item key=question name={`questions-${id}`}>
            <Ui.Accordion.Trigger> {text(question)} </Ui.Accordion.Trigger>
            <Ui.Accordion.Panel> {text(answer)} </Ui.Accordion.Panel>
          </Ui.Accordion.Item>
        )
        ->WeftDom.Jsx.array}
      </Ui.Accordion.Root>
    </Ui.Stack>
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
      <Ui.Stack gap=#xl>
        <Breadcrumbs
          trail=[(Db.categoryName(summary.category), `/c/${summary.category}`)] current=summary.name
        />
        <Ui.Grid template="1fr 1fr" gap=#xxl stackBelow=#md dataId={`product-${summary.id}`}>
          <Gallery name=summary.name hue=summary.hue />
          <Ui.Stack gap=#sm align=#start>
            <Ui.Stack direction=#row gap=#sm align=#center>
              <Ui.Heading level=#h1 dataId="product-name"> {text(summary.name)} </Ui.Heading>
              <WishlistButton productId=summary.id saved={wishlist(request)->Set.has(summary.id)} />
            </Ui.Stack>
            <Ui.Text tone=#muted dataId="rating">
              {text(`★ ${Float.toFixed(summary.rating, ~digits=1)}`)}
            </Ui.Text>
            <ProductOffer slug=summary.slug variants=product.variants selected=firstSku.sku>
              <OfferPart sku=firstSku.sku request />
            </ProductOffer>
            <Ui.Text dataId="description"> {text(product.description)} </Ui.Text>
          </Ui.Stack>
        </Ui.Grid>
        <section dataId="reviews-section">
          <Ui.Heading level=#h2 size=#lg> {text("Reviews")} </Ui.Heading>
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
      </Ui.Stack>
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
    <Ui.DescriptionList.Root dataId="summary" detailsAlign=#end>
      <Ui.DescriptionList.Term> {text("Subtotal")} </Ui.DescriptionList.Term>
      <Ui.DescriptionList.Details>
        <Price dataId="summary-subtotal" cents=cart.subtotal />
      </Ui.DescriptionList.Details>
      {cart.discount > 0
        ? <>
            <Ui.DescriptionList.Term>
              {text(`Discount (${cart.promo->Option.getOr("")})`)}
            </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details>
              <Price dataId="summary-discount" cents={-cart.discount} />
            </Ui.DescriptionList.Details>
          </>
        : WeftDom.Jsx.null}
      <Ui.DescriptionList.Term> {text("Total")} </Ui.DescriptionList.Term>
      <Ui.DescriptionList.Details>
        <Price dataId="summary-total" cents=total />
      </Ui.DescriptionList.Details>
      <Ui.DescriptionList.Term> {text("Points")} </Ui.DescriptionList.Term>
      <Ui.DescriptionList.Details dataId="summary-points">
        {text(Int.toString(total / 100))}
      </Ui.DescriptionList.Details>
    </Ui.DescriptionList.Root>
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
      <Ui.Stack gap=#lg>
        <Ui.Heading level=#h1 dataId="cart-title"> {text("Your cart")} </Ui.Heading>
        <Ui.Grid template="minmax(0, 1fr) 300px" gap=#xl stackBelow=#md>
          <CartLines />
          <Ui.Card.Root as_=#aside ariaLabel="Summary">
            <CartSummaryFrame>
              <CartSummaryPart request />
            </CartSummaryFrame>
            <PromoForm applied=request.session.promo />
            <Link
              dataId="checkout-link"
              className={Ui.Button.className(~variant=#primary, ~fullWidth=true, ())}
              href="/checkout"
            >
              {text("Check out")}
            </Link>
          </Ui.Card.Root>
        </Ui.Grid>
      </Ui.Stack>
    </Shell>
}

module CheckoutPage = {
  @weft.component({kind: Server})
  let make = (~request: request) => {
    let cart = Session.cart(request.session)
    <Shell request>
      <Ui.Heading level=#h1 dataId="checkout-title"> {text("Checkout")} </Ui.Heading>
      // An empty cart is redirected to the cart (`Server`), so there's something to check out.
      <CheckoutForm total={cart.subtotal - cart.discount} count=cart.count />
    </Shell>
  }
}

module DeliveryEstimate = {
  @weft.component({kind: Server})
  let make = async (~order: order, ~request: request) => {
    await Latency.wait(`estimate:${order.id}`, ~signal=request.signal)
    <Ui.Text dataId="estimate">
      {text(
        switch order.status {
        | Delivered => "Delivered."
        | Shipped => "Arriving tomorrow."
        | Placed | Packed => "Arriving in 3–5 days."
        },
      )}
    </Ui.Text>
  }
}

/** How often the order page refreshes itself, in milliseconds (`None`: never). */
let pollEvery: ref<option<int>> = ref(Some(3000))

module OrderPage = {
  @weft.component({kind: Server})
  let make = (~order: order, ~request: request) =>
    <Shell request>
      <Ui.Stack gap=#lg>
        <Ui.Heading level=#h1 dataId="order-title"> {text(`Order ${order.id}`)} </Ui.Heading>
        <Ui.Text dataId="order-status"> {text(`Status: ${statusLabel(order.status)}`)} </Ui.Text>
        <OrderTracker status=order.status every=?pollEvery.contents />
        <Ui.Table.Root dataId="order-lines" ariaLabel="What's in it">
          <Ui.Table.Head>
            <Ui.Table.Row>
              <Ui.Table.HeaderCell> {text("Item")} </Ui.Table.HeaderCell>
              <Ui.Table.HeaderCell> {text("Variant")} </Ui.Table.HeaderCell>
              <Ui.Table.HeaderCell numeric=true> {text("Quantity")} </Ui.Table.HeaderCell>
            </Ui.Table.Row>
          </Ui.Table.Head>
          <Ui.Table.Body>
            {order.lines
            ->Array.map(line =>
              <Ui.Table.Row key=line.sku>
                <Ui.Table.HeaderCell scope=#row> {text(line.name)} </Ui.Table.HeaderCell>
                <Ui.Table.Cell> {text(line.variant)} </Ui.Table.Cell>
                <Ui.Table.Cell numeric=true> {text(Int.toString(line.quantity))} </Ui.Table.Cell>
              </Ui.Table.Row>
            )
            ->WeftDom.Jsx.array}
          </Ui.Table.Body>
        </Ui.Table.Root>
        <Ui.Text weight=#semibold>
          {text("Total: ")}
          <Price dataId="order-total" cents=order.total />
        </Ui.Text>
        <Weft.Suspense fallback={loading("estimate-loading", "Estimating delivery…")}>
          <DeliveryEstimate order request />
        </Weft.Suspense>
      </Ui.Stack>
    </Shell>
}

module AccountPage = {
  @weft.component({kind: Server})
  let make = (~name: string, ~request: request) => {
    let user = Db.user(name)
    let saved = user.wishlist->Set.values->Iterator.toArray->Array.filterMap(Db.summary)
    <Shell request>
      <Ui.Stack gap=#xl>
        <Ui.Heading level=#h1 dataId="account-title"> {text(`${name}'s account`)} </Ui.Heading>
        <Ui.Stack as_=#section gap=#md dataId="orders">
          <Ui.Heading level=#h2 size=#lg> {text("Orders")} </Ui.Heading>
          {user.orders == []
            ? <Ui.EmptyState.Root bordered=true dataId="no-orders">
                <Ui.EmptyState.Title> {text("No orders yet.")} </Ui.EmptyState.Title>
              </Ui.EmptyState.Root>
            : <Ui.Table.Root ariaLabel="Orders">
                <Ui.Table.Head>
                  <Ui.Table.Row>
                    <Ui.Table.HeaderCell> {text("Order")} </Ui.Table.HeaderCell>
                    <Ui.Table.HeaderCell> {text("Status")} </Ui.Table.HeaderCell>
                    <Ui.Table.HeaderCell numeric=true> {text("Total")} </Ui.Table.HeaderCell>
                  </Ui.Table.Row>
                </Ui.Table.Head>
                <Ui.Table.Body>
                  {user.orders
                  ->Array.filterMap(Db.findOrder)
                  ->Array.map(order =>
                    <Ui.Table.Row key=order.id>
                      <Ui.Table.HeaderCell scope=#row>
                        <Link dataId={`order-link-${order.id}`} href={`/orders/${order.id}`}>
                          {text(order.id)}
                        </Link>
                      </Ui.Table.HeaderCell>
                      <Ui.Table.Cell> {text(statusLabel(order.status))} </Ui.Table.Cell>
                      <Ui.Table.Cell numeric=true>
                        <Price cents=order.total />
                      </Ui.Table.Cell>
                    </Ui.Table.Row>
                  )
                  ->WeftDom.Jsx.array}
                </Ui.Table.Body>
              </Ui.Table.Root>}
        </Ui.Stack>
        <Ui.Stack as_=#section gap=#md dataId="wishlist">
          <Ui.Heading level=#h2 size=#lg> {text("Saved for later")} </Ui.Heading>
          {saved == []
            ? <Ui.EmptyState.Root bordered=true dataId="no-saved">
                <Ui.EmptyState.Title> {text("Nothing saved yet.")} </Ui.EmptyState.Title>
              </Ui.EmptyState.Root>
            : <Ui.Grid minItemWidth="200px" gap=#lg> {cards(saved, request)} </Ui.Grid>}
        </Ui.Stack>
      </Ui.Stack>
    </Shell>
  }
}

module SignInPage = {
  @weft.component({kind: Server})
  let make = (~next: string, ~request: request) =>
    <Shell request>
      <Ui.Heading level=#h1 dataId="signin-title"> {text("Sign in")} </Ui.Heading>
      <SignInForm next />
    </Shell>
}

module NotFound = {
  @weft.component({kind: Server})
  let make = (~request: request) =>
    <Shell request>
      <Ui.EmptyState.Root>
        <Ui.EmptyState.Title level=#h1 dataId="not-found">
          {text("Not found")}
        </Ui.EmptyState.Title>
        <Ui.EmptyState.Description>
          {text("There's nothing at this address.")}
        </Ui.EmptyState.Description>
        <Ui.EmptyState.Action>
          <Link href="/" className={Ui.Button.className(~variant=#primary, ())}>
            {text("Back to the store")}
          </Link>
        </Ui.EmptyState.Action>
      </Ui.EmptyState.Root>
    </Shell>
}
