@@weft.server

/***
The server components every page uses: the shell (the header and footer, inside the `ShopShell`
entrypoint, which provides the page's context), and product cards, whose stock streams in, each
under a boundary of its own.
*/

open Types
open WeftCss

module Styles = {
  let app = Css.class({
    maxWidth: Px(1100),
    margin: Pair(Zero, Auto),
    padding: Four(Zero, Px(16), Px(48), Px(16)),
  })
  let header = Css.class({
    display: Flex,
    flexWrap: Wrap,
    gap: Pair(Px(12), Px(20)),
    alignItems: Center,
    padding: Pair(Px(16), Zero),
    borderBottom: Theme.hairline(),
  })
  let logo = Css.class({fontWeight: 700, fontSize: Px(20), textDecoration: None})
  let nav = Css.class({
    display: Flex,
    gap: Px(14),
    selectors: [("a", Css.style({textDecoration: None, color: Var(Theme.muted)}))],
  })
  let headerTools = Css.class({display: Flex, gap: Px(10), alignItems: Center})
  let main = Css.class({paddingTop: Px(20)})
  let footer = Css.class({marginTop: Px(48), color: Var(Theme.muted), fontSize: Px(13)})
  let card = Css.class({
    backgroundColor: Named("white"),
    border: Theme.hairline(),
    borderRadius: Px(10),
    padding: Px(10),
  })
  let cardLink = Css.class({textDecoration: None})
  let cardName = Css.class({fontSize: Px(15), margin: Four(Px(8), Zero, Px(4), Zero)})
  let cardMeta = Css.class({display: Flex, justifyContent: SpaceBetween, alignItems: Center})
  let stock = Css.class({fontSize: Px(13), color: Hex("2f6b3a")})
  let stockOut = Css.class({color: Var(Theme.sale)})
  let stockLoading = Css.class({color: Var(Theme.muted)})
}

/** A product's stock's classes: its semantic ones (which tests find it by), and its style. */
let stockClass = stock => stock == 0 ? Css.cx([Styles.stock, Styles.stockOut]) : Styles.stock

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

module StockBadge = {
  /** How many are left, from the (slow) inventory service. */
  @weft.component({kind: Server})
  let make = async (~id, ~signal) => {
    await Latency.wait(`stock:${id}`, ~signal)
    let stock = Db.productStock(id)
    <span className={stockClass(stock)} id={`stock-${id}`}>
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
    <article className={Styles.card} id={`card-${summary.id}`}>
      <Link className={Styles.cardLink} href={`/p/${summary.slug}`}>
        <div className={Theme.picture} style={Theme.pictureVars(~hue=summary.hue)} />
        <h3 className={Styles.cardName}> {text(summary.name)} </h3>
      </Link>
      <div className={Styles.cardMeta}>
        <Price cents=summary.price compareAt=?summary.compareAt />
        <WishlistButton productId=summary.id saved />
      </div>
      <Weft.Suspense
        fallback={<span
          className={Css.cx([Styles.stock, Styles.stockLoading])}
          id={`stock-loading-${summary.id}`}
          ariaBusy="true"
        >
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
    <header id="header" className=Styles.header>
      <Link id="logo" className=Styles.logo href="/"> {text("Loom & Co.")} </Link>
      <nav id="nav" className=Styles.nav>
        {Db.categories
        ->Array.map(((slug, name)) =>
          <Link key=slug id={`nav-${slug}`} href={`/c/${slug}`}> {text(name)} </Link>
        )
        ->WeftDom.Jsx.array}
      </nav>
      <SearchBox initial=query />
      <div className={Styles.headerTools}>
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
      <div id="app" className=Styles.app>
        <Header query=request.query />
        <main id="main" className=Styles.main> children </main>
        <footer id="footer" className=Styles.footer>
          {text("Loom & Co. — a Weft example. Nothing here is for sale.")}
        </footer>
      </div>
    </ShopShell>
  }
}

let loading = (id, message) =>
  <p id className={Theme.placeholder} ariaBusy="true"> {text(message)} </p>
