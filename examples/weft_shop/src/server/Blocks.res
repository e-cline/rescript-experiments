@@weft.server

/***
Renders the CMS's blocks (`Cms`). Each block is a server component waiting on its own service, in a
`Suspense` boundary of its own (so the page streams, block by block), inside a `BlockFrame`
entrypoint (an error boundary, with Retry, and the block fetched again from its own route,
`/blocks/<page>/<id>`, which renders `Content`). Containers (tabs, columns, an experiment) render
their blocks the same way, so a block deep in a tab streams, fails and refetches by itself too.
*/

open Types
open Ui
open WeftCss

module Styles = {
  let hero = Css.class({
    padding: Pair(Px(36), Px(28)),
    borderRadius: Px(12),
    background: "linear-gradient(120deg, #f3dcc8, #e9c8a9)",
    selectors: [("p", Css.style({margin: Four(Px(6), Zero, Px(16), Zero)}))],
  })
  let heroCool = Css.class({background: "linear-gradient(120deg, #d7e3ee, #bfd2e3)"})
  let tiles = Css.class({
    selectors: [
      (
        "ul",
        Css.style({
          display: Grid,
          gridTemplateColumns: "repeat(4, 1fr)",
          gap: Px(12),
          padding: Zero,
          listStyle: None,
        }),
      ),
      (
        "a",
        Css.style({
          display: Block,
          padding: Px(20),
          backgroundColor: Named("white"),
          border: Theme.hairline(),
          borderRadius: Px(10),
          textDecoration: None,
        }),
      ),
    ],
    media: [
      Css.media(
        ~query="(max-width: 720px)",
        {selectors: [("ul", Css.style({gridTemplateColumns: "repeat(2, 1fr)"}))]},
      ),
    ],
  })
  let promo = Css.class({
    display: Flex,
    justifyContent: SpaceBetween,
    alignItems: Center,
    padding: Pair(Px(14), Px(18)),
    border: `1px dashed ${Theme.value(Theme.accent)}`,
    borderRadius: Px(10),
  })
  let liveDeals = Css.class({
    selectors: [
      ("ul", Css.style({padding: Zero, listStyle: None})),
      (
        "li",
        Css.style({
          display: Flex,
          gap: Px(8),
          padding: Pair(Px(6), Zero),
          borderBottom: Theme.hairline(),
        }),
      ),
    ],
  })
  let columns = Css.class({
    display: Grid,
    gridTemplateColumns: "1fr 1fr",
    gap: Px(24),
    media: [Css.media(~query="(max-width: 720px)", {gridTemplateColumns: "1fr"})],
  })
}

/** What a rail's source has, for this shopper. */
let railItems = (source: Cms.source, request: request) =>
  switch source {
  | Featured => Db.featured()
  | Deals => Db.deals()
  | Category(slug) => Db.inCategory(slug)
  | Recommended =>
    switch request.session.viewed {
    | [] => Db.featured()->Array.toReversed
    | viewed => viewed->Array.flatMap(Db.alsoBought)
    }->Array.filter(summary => !(request.session.viewed->Array.includes(summary.id)))
  | RecentlyViewed => request.session.viewed->Array.filterMap(Db.summary)
  | BuyAgain =>
    request.session.user
    ->Option.mapOr([], name => Db.user(name).orders)
    ->Array.filterMap(Db.findOrder)
    ->Array.flatMap(order => order.lines)
    ->Array.filterMap(line => Db.findBySlug(line.slug)->Option.map(product => product.summary))
  }

/** Each summary once, in order. */
let unique = (summaries: array<summary>) =>
  summaries->Array.filterWithIndex((summary, index) =>
    summaries->Array.findIndex(other => other.id == summary.id) == index
  )

/** Which service a rail's data comes from: recommendations are the flaky one. */
let railGate = (id, source: Cms.source) =>
  switch source {
  | Recommended => `recs:${id}`
  | _ => `rail:${id}`
  }

/** A block's own content, once its service has answered. */
module Body = {
  @weft.component({kind: Server})
  let make = async (~block: Cms.block, ~request: request) => {
    let {signal} = request
    switch block.kind {
    | Hero({title, subtitle, cta: (label, href), tone}) =>
      await Latency.wait(`block:${block.id}`, ~signal)
      <div
        className={Css.cx([Styles.hero, tone == "cool" ? Styles.heroCool : ""])}
        dataId={`hero-${block.id}`}
      >
        <WeftUi.Heading level=#h1 size=#xxl> {text(title)} </WeftUi.Heading>
        <p> {text(subtitle)} </p>
        <Link className={WeftUi.Button.className(~variant=#primary, ())} href> {text(label)} </Link>
      </div>
    | Rail({title, source, limit}) =>
      await Latency.wait(railGate(block.id, source), ~signal)
      let items = railItems(source, request)->unique->Array.slice(~start=0, ~end=limit)
      switch items {
      | [] => WeftDom.Jsx.null
      | items =>
        <Carousel id=block.id title count={Array.length(items)}> {cards(items, request)} </Carousel>
      }
    | CategoryTiles({title}) =>
      await Latency.wait(`block:${block.id}`, ~signal)
      <div className={Styles.tiles}>
        <WeftUi.Heading level=#h2 size=#lg> {text(title)} </WeftUi.Heading>
        <ul>
          {Db.categories
          ->Array.map(((slug, name)) =>
            <li key=slug>
              <Link dataId={`tile-${slug}`} href={`/c/${slug}`}>
                {text(`${name} (${Int.toString(Array.length(Db.inCategory(slug)))})`)}
              </Link>
            </li>
          )
          ->WeftDom.Jsx.array}
        </ul>
      </div>
    | Promo({code, text: offer, endsInMinutes}) =>
      await Latency.wait(`block:${block.id}`, ~signal)
      let now = Date.now()
      <div className={Styles.promo} dataId={`promo-${block.id}`}>
        <p>
          {text(`${offer} with code `)}
          <b> {text(code)} </b>
        </p>
        <Countdown
          id={`countdown-${block.id}`} endsAt={now +. Int.toFloat(endsInMinutes * 60_000)} now
        />
      </div>
    | LiveDeals({title}) =>
      await Latency.wait(`block:${block.id}`, ~signal)
      <div className={Styles.liveDeals}>
        <WeftUi.Heading level=#h2 size=#lg> {text(title)} </WeftUi.Heading>
        <ul dataId="live-list">
          {Db.deals()
          ->Array.slice(~start=0, ~end=4)
          ->Array.map(summary =>
            <li key=summary.id dataId={`live-${summary.id}`}>
              <Link href={`/p/${summary.slug}`}> {text(summary.name)} </Link>
              {text(" ")}
              <Price cents=summary.price compareAt=?summary.compareAt />
              <span dataId={`left-${summary.id}`}>
                {text(` ${Int.toString(Db.productStock(summary.id))} left`)}
              </span>
            </li>
          )
          ->WeftDom.Jsx.array}
        </ul>
      </div>
    | Newsletter => <Newsletter />
    | Text({title, body}) =>
      <div dataId={`text-${block.id}`}>
        <WeftUi.Heading level=#h2 size=#lg> {text(title)} </WeftUi.Heading>
        {body == "" ? WeftDom.Jsx.null : <WeftUi.Text> {text(body)} </WeftUi.Text>}
      </div>
    // Containers are rendered by `Block`.
    | Tabs(_) | Columns(_) | Experiment(_) => WeftDom.Jsx.null
    }
  }
}

let skeleton = (block: Cms.block) =>
  <div className={Theme.placeholder} dataId={`loading-${block.id}`} ariaBusy="true">
    {text(
      switch block.kind {
      | Rail({title}) | LiveDeals({title}) => `Loading ${title->String.toLowerCase}…`
      | _ => "Loading…"
      },
    )}
  </div>

/** What a block's frame shows, and what its route sends when it's refetched. */
module Content = {
  @weft.component({kind: Server})
  let make = (~block: Cms.block, ~request: request) =>
    <Weft.Suspense fallback={skeleton(block)}>
      <Body block request />
    </Weft.Suspense>
}

/**
A block, framed (or, for a container, its blocks, each framed): a plain function rather than a
component, since containers render blocks again, keyed by `key` (the block's id, or the experiment's
for the variant it picked).
*/
let rec framed = (block: Cms.block, ~key=block.id, ~page: string, ~request: request) =>
  switch block.kind {
  | Tabs({tabs}) =>
    <WeftUi.TabsEntry
      key
      dataId={`tabs-${block.id}`}
      variant=#pills
      labels={tabs->Array.map(((label, _)) => label)}
      panels={tabs->Array.map(((_, blocks)) => blockList(blocks, ~page, ~request))}
    />
  | Columns({columns}) =>
    <div key className={Styles.columns} dataId={`columns-${block.id}`}>
      {columns
      ->Array.mapWithIndex((blocks, index) =>
        <div key={Int.toString(index)}> {blockList(blocks, ~page, ~request)} </div>
      )
      ->WeftDom.Jsx.array}
    </div>
  | Experiment({a, b}) => framed(request.session.bucket == "b" ? b : a, ~key, ~page, ~request)
  | LiveDeals({everySeconds}) =>
    <BlockFrame
      key
      id=block.id
      src={`/blocks/${page}/${block.id}`}
      refreshEvery=?{everySeconds > 0 ? Some(everySeconds) : None}
    >
      <Content block request />
    </BlockFrame>
  | _ =>
    <BlockFrame key id=block.id src={`/blocks/${page}/${block.id}`}>
      <Content block request />
    </BlockFrame>
  }
and blockList = (blocks: array<Cms.block>, ~page, ~request) =>
  blocks->Array.map(child => framed(child, ~page, ~request))->WeftDom.Jsx.array
