@@weft.server

/***
The server components every page uses: the shell (the header and footer, inside the `ShopShell`
entrypoint, which provides the page's context), and product cards, whose stock streams in, each
under a boundary of its own.
*/

open Types
open WeftCss
module Jsx = WeftDom.Jsx

module Styles = {
  let app = Css.class({paddingBlockEnd: Px(48)})
  let header = Css.class({
    display: Flex,
    flexWrap: Wrap,
    gap: Pair(Px(12), Px(20)),
    alignItems: Center,
    padding: Pair(Px(16), Zero),
    borderBottom: Theme.hairline(),
  })
  let logo = Css.class({fontWeight: 700, fontSize: Px(20)})
  let navList = Css.class({flexDirection: Row, gap: Px(14)})
  let main = Css.class({paddingTop: Px(20)})
  let footer = Css.class({marginTop: Px(48)})
  let cardLink = Css.class({
    display: Flex,
    flexDirection: Column,
    gap: Px(8),
    color: Raw("inherit"),
    textDecoration: None,
    borderRadius: Px(8),
    focusVisible: WeftUi.Tokens.focusVisible(),
  })
  let cardName = Css.class({fontSize: Px(15), fontWeight: 600, margin: Zero})
}

/** A product's stock's tone: sold out is the sale colour, a few left the accent, else in stock. */
let stockTone = (stock): WeftUi.Variants.tone =>
  switch stock {
  | 0 => #danger
  | stock if stock <= 3 => #accent
  | _ => #success
  }

/** What a server component needs from the request: the shopper's session, and the request's signal. */
type request = {
  session: Session.t,
  signal: Latency.signal,
  /** The search box's text, on the search page. */
  query: string,
}

let text = Jsx.string

let wishlist = (request: request) =>
  request.session.user->Option.mapOr(Set.make(), name => Db.user(name).wishlist)

module StockBadge = {
  /** How many are left, from the (slow) inventory service. */
  @weft.component({kind: Server})
  let make = async (~id, ~signal) => {
    await Latency.wait(`stock:${id}`, ~signal)
    let stock = Db.productStock(id)
    <WeftUi.Badge tone={stockTone(stock)} size=#sm dataId={`stock-${id}`}>
      {text(
        switch stock {
        | 0 => "Sold out"
        | stock if stock <= 3 => `Only ${Int.toString(stock)} left`
        | _ => "In stock"
        },
      )}
    </WeftUi.Badge>
  }
}

module ProductCard = {
  @weft.component({kind: Server})
  let make = (~summary: summary, ~saved: bool, ~signal) =>
    <WeftUi.Card.Root as_=#article padding=#sm dataId={`card-${summary.id}`}>
      <Link className={Styles.cardLink} href={`/p/${summary.slug}`}>
        <div className={Theme.picture} style={Theme.pictureVars(~hue=summary.hue)} />
        <h3 className={Styles.cardName}> {text(summary.name)} </h3>
      </Link>
      <SaleBadge summary />
      <WeftUi.Stack direction=#row justify=#between align=#center gap=#sm>
        <Price cents=summary.price compareAt=?summary.compareAt />
        <WishlistButton productId=summary.id saved />
      </WeftUi.Stack>
      // In a box of its own: the card is a column, which would stretch the badge across it.
      <div>
        <Weft.Suspense
          fallback={<WeftUi.Text
            as_=#span
            tone=#muted
            size=#sm
            dataId={`stock-loading-${summary.id}`}
            attrs={{ariaBusy: "true"}}
          >
            {text("Checking stock…")}
          </WeftUi.Text>}
        >
          <StockBadge id=summary.id signal />
        </Weft.Suspense>
      </div>
    </WeftUi.Card.Root>
}

/** Cards for `summaries`, keyed. */
let cards = (summaries: array<summary>, request) => {
  let saved = wishlist(request)
  summaries
  ->Array.map(summary =>
    <ProductCard key=summary.id summary saved={saved->Set.has(summary.id)} signal=request.signal />
  )
  ->Jsx.array
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
    <header dataId="header" className=Styles.header>
      <Link
        dataId="logo"
        className={WeftUi.Link.className(~tone=#inherit, ~underline=#none, ())}
        href="/"
      >
        <span className=Styles.logo> {text("Loom & Co.")} </span>
      </Link>
      <nav dataId="nav" ariaLabel="Categories">
        <WeftUi.List.Root className=Styles.navList>
          {Db.categories
          ->Array.map(((slug, name)) =>
            <WeftUi.List.Item key=slug>
              <Link
                dataId={`nav-${slug}`}
                className={WeftUi.Link.className(~tone=#muted, ~underline=#hover, ())}
                href={`/c/${slug}`}
              >
                {text(name)}
              </Link>
            </WeftUi.List.Item>
          )
          ->Jsx.array}
        </WeftUi.List.Root>
      </nav>
      <SearchBox initial=query />
      <WeftUi.Stack direction=#row gap=#sm align=#center>
        <CurrencySelect />
        <AccountMenu />
        <CartBadge />
      </WeftUi.Stack>
    </header>
}

module Shell = {
  @weft.component({kind: Server})
  let make = (~request: request, ~children) => {
    let session = request.session
    <ShopShell currency=session.currency user=session.user cart={Session.cart(session)}>
      <WeftUi.Container size=#lg dataId="app" className={Css.cx([Theme.root, Styles.app])}>
        <Header query=request.query />
        <main dataId="main" className=Styles.main> children </main>
        <footer dataId="footer" className=Styles.footer>
          <WeftUi.Text tone=#muted size=#sm>
            {text("Loom & Co. — a Weft example. Nothing here is for sale.")}
          </WeftUi.Text>
        </footer>
      </WeftUi.Container>
    </ShopShell>
  }
}

let loading = (id, message) =>
  <p dataId=id className={Theme.placeholder} ariaBusy="true"> {text(message)} </p>
