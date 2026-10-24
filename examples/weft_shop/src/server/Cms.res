@@weft.server

/***
The "CMS": what the home page and each category page are made of, as a tree of blocks the server
decides on for each request (server-driven UI). The layouts are data, kept here and changed at
runtime (the tests move, add and remove blocks), and each shopper's is personalised: signed in or
not, and which half of the experiment they're in. `Blocks` renders them.
*/

/** Where a rail of products comes from. */
type source =
  | Featured
  | Deals
  | Category(string)
  /** For the signed-in shopper (from a flaky service). */
  | Recommended
  | RecentlyViewed
  | BuyAgain

type rec block = {id: string, kind: kind}
and kind =
  | Hero({title: string, subtitle: string, cta: (string, string), tone: string})
  | Rail({title: string, source: source, limit: int})
  | CategoryTiles({title: string})
  | Promo({code: string, text: string, endsInMinutes: int})
  | Tabs({tabs: array<(string, array<block>)>})
  | Columns({columns: array<array<block>>})
  /** Refetched every `everySeconds` by the client. */
  | LiveDeals({title: string, everySeconds: int})
  | Newsletter
  /** `a` for half the shoppers, `b` for the other half. */
  | Experiment({a: block, b: block})
  | Text({title: string, body: string})

/** Who the layout is for. */
type viewer = {user: option<string>, bucket: string}

/** How often the live deals refresh, in seconds (0: never, the tests' default). */
let liveEvery = ref(5)

let defaultHome = () => [
  {
    id: "hero",
    kind: Hero({
      title: "Made to last",
      subtitle: "Everyday things, built well.",
      cta: ("Shop shoes", "/c/shoes"),
      tone: "warm",
    }),
  },
  {
    id: "promo",
    kind: Experiment({
      a: {
        id: "promo-a",
        kind: Promo({code: "WEFT10", text: "10% off everything", endsInMinutes: 90}),
      },
      b: {
        id: "promo-b",
        kind: Promo({code: "LOOM20", text: "20% off orders over $100", endsInMinutes: 45}),
      },
    }),
  },
  {id: "featured", kind: Rail({title: "Featured", source: Featured, limit: 6})},
  {id: "live", kind: LiveDeals({title: "Flash deals", everySeconds: liveEvery.contents})},
  {id: "categories", kind: CategoryTiles({title: "Shop by category"})},
  {
    id: "tabs",
    kind: Tabs({
      tabs: [
        (
          "Shoes",
          [{id: "tab-shoes", kind: Rail({title: "Shoes", source: Category("shoes"), limit: 4})}],
        ),
        (
          "Outerwear",
          [
            {
              id: "tab-outerwear",
              kind: Rail({title: "Outerwear", source: Category("outerwear"), limit: 4}),
            },
          ],
        ),
        (
          "Bags",
          [{id: "tab-bags", kind: Rail({title: "Bags", source: Category("bags"), limit: 4})}],
        ),
      ],
    }),
  },
  {
    id: "bottom",
    kind: Columns({
      columns: [
        [
          {
            id: "story",
            kind: Text({title: "Our story", body: "Fewer, better things, since 2026."}),
          },
        ],
        [{id: "newsletter", kind: Newsletter}],
      ],
    }),
  },
]

let defaultCategory = slug => [
  {
    id: `${slug}-hero`,
    kind: Hero({
      title: Db.categoryName(slug),
      subtitle: `Everything in ${Db.categoryName(slug)->String.toLowerCase}.`,
      cta: ("See the deals", "/#live"),
      tone: "cool",
    }),
  },
]

let layouts: Map.t<string, array<block>> = Map.make()

let seed = () => {
  layouts->Map.clear
  layouts->Map.set("home", defaultHome())
  Db.categories->Array.forEach(((slug, _)) => layouts->Map.set(`c-${slug}`, defaultCategory(slug)))
}

seed()

let stored = page => layouts->Map.get(page)->Option.getOr([])

/** The blocks only signed-in shoppers see, after the hero. */
let personal = name => [
  {
    id: "welcome",
    kind: Hero({
      title: `Welcome back, ${name}`,
      subtitle: "Picked for you, below.",
      cta: ("Your account", "/account"),
      tone: "warm",
    }),
  },
  {id: "for-you", kind: Rail({title: "Recommended for you", source: Recommended, limit: 4})},
  {id: "buy-again", kind: Rail({title: "Buy again", source: BuyAgain, limit: 4})},
]

/** `page`'s blocks, for `viewer`. */
let layout = (page, viewer) => {
  let blocks = stored(page)
  let blocks = switch (page, viewer.user) {
  | ("home", Some(name)) =>
    // The welcome replaces the hero.
    [...personal(name), ...blocks->Array.filter(block => block.id != "hero")]
  | _ => blocks
  }
  page == "home"
    ? [
        ...blocks,
        {id: "recent", kind: Rail({title: "Recently viewed", source: RecentlyViewed, limit: 6})},
      ]
    : blocks
}

/** The block `id` in `blocks`, wherever it is in the tree. */
let rec find = (blocks: array<block>, id) =>
  blocks->Array.findMap(block =>
    if block.id == id {
      Some(block)
    } else {
      switch block.kind {
      | Tabs({tabs}) => tabs->Array.findMap(((_, blocks)) => find(blocks, id))
      | Columns({columns}) => columns->Array.findMap(blocks => find(blocks, id))
      | Experiment({a, b}) => find([a, b], id)
      | _ => None
      }
    }
  )

// What the tests change

/** Moves `id` (a top-level block of `page`) to position `index`. */
let move = (page, id, index) => {
  let blocks = stored(page)
  switch blocks->Array.find(block => block.id == id) {
  | Some(block) =>
    let rest = blocks->Array.filter(other => other.id != id)
    rest->Array.splice(~start=index, ~remove=0, ~insert=[block])
    layouts->Map.set(page, rest)
  | None => ()
  }
}

let remove = (page, id) =>
  layouts->Map.set(page, stored(page)->Array.filter(block => block.id != id))

/** Inserts a text block `id` at `index`. */
let insertText = (page, id, index, title) => {
  let blocks = stored(page)->Array.copy
  blocks->Array.splice(~start=index, ~remove=0, ~insert=[{id, kind: Text({title, body: ""})}])
  layouts->Map.set(page, blocks)
}

let setHeroTitle = (page, title) =>
  layouts->Map.set(
    page,
    stored(page)->Array.map(block =>
      switch block.kind {
      | Hero(hero) => {...block, kind: Hero({...hero, title})}
      | _ => block
      }
    ),
  )
