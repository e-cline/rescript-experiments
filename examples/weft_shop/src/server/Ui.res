@@weft.server

/***
The server components every page uses: the shell (the header and footer, inside the `ShopShell`
entrypoint, which provides the page's context), and product cards, whose stock streams in, each
under a boundary of its own.
*/

open Types

/** What a server component needs from the request: the shopper's session, and the request's signal. */
type request = {
  session: Session.t,
  signal: Latency.signal,
  /** The search box's text, on the search page. */
  query: string,
}

let text = WeftDom.Jsx.string

let wishlist = (request: request) =>
  request.session.user->Option.mapOr(Set.make(), name => Db.user(name).wishlist)

let picture = (summary: summary) =>
  Dict.fromArray([
    (
      "background",
      `linear-gradient(135deg, hsl(${Int.toString(summary.hue)} 45% 70%), hsl(${Int.toString(
          summary.hue + 30,
        )} 35% 40%))`,
    ),
  ])

module StockBadge = {
  /** How many are left, from the (slow) inventory service. */
  @weft.component({kind: Server})
  let make = async (~id, ~signal) => {
    await Latency.wait(`stock:${id}`, ~signal)
    let stock = Db.productStock(id)
    <span className={stock == 0 ? "stock out" : "stock"} id={`stock-${id}`}>
      {text(
        switch stock {
        | 0 => "Sold out"
        | stock if stock <= 3 => `Only ${Int.toString(stock)} left`
        | _ => "In stock"
        },
      )}
    </span>
  }
}

module ProductCard = {
  @weft.component({kind: Server})
  let make = (~summary: summary, ~saved: bool, ~signal) =>
    <article className="card" id={`card-${summary.id}`}>
      <Link className="card-link" href={`/p/${summary.slug}`}>
        <div className="picture" style={picture(summary)} />
        <h3 className="card-name"> {text(summary.name)} </h3>
      </Link>
      <div className="card-meta">
        <Price cents=summary.price compareAt=?summary.compareAt />
        <WishlistButton productId=summary.id saved />
      </div>
      <Weft.Suspense
        fallback={<span className="stock loading" id={`stock-loading-${summary.id}`}>
          {text("Checking stock…")}
        </span>}
      >
        <StockBadge id=summary.id signal />
      </Weft.Suspense>
    </article>
}

/** Cards for `summaries`, keyed. */
let cards = (summaries: array<summary>, request) => {
  let saved = wishlist(request)
  summaries
  ->Array.map(summary =>
    <ProductCard key=summary.id summary saved={saved->Set.has(summary.id)} signal=request.signal />
  )
  ->WeftDom.Jsx.array
}

/** A grid's items: the cards, and the names the client filters them by. */
let gridItems = (summaries: array<summary>, request): array<gridItem> => {
  let saved = wishlist(request)
  summaries->Array.map(summary => {
    key: summary.id,
    name: summary.name,
    card: <ProductCard summary saved={saved->Set.has(summary.id)} signal=request.signal />,
  })
}

module Header = {
  @weft.component({kind: Server})
  let make = (~query) =>
    <header id="header">
      <Link id="logo" href="/"> {text("Loom & Co.")} </Link>
      <nav id="nav">
        {Db.categories
        ->Array.map(((slug, name)) =>
          <Link key=slug id={`nav-${slug}`} href={`/c/${slug}`}> {text(name)} </Link>
        )
        ->WeftDom.Jsx.array}
      </nav>
      <SearchBox initial=query />
      <div className="header-tools">
        <CurrencySelect />
        <AccountMenu />
        <CartBadge />
      </div>
    </header>
}

module Shell = {
  @weft.component({kind: Server})
  let make = (~request: request, ~children) => {
    let session = request.session
    <ShopShell currency=session.currency user=session.user cart={Session.cart(session)}>
      <div id="app">
        <Header query=request.query />
        <main id="main"> children </main>
        <footer id="footer">
          {text("Loom & Co. — a Weft example. Nothing here is for sale.")}
        </footer>
      </div>
    </ShopShell>
  }
}

let loading = (id, message) => <p id className="loading"> {text(message)} </p>
