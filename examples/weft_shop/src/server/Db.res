@@weft.server

/***
The store's "database", in memory: the catalog (made the same way every time, so tests can name
products), stock, reviews, users and orders. The slow parts of the pages call it through
`Latency`; this module answers at once.
*/

open Types

let categories = [
  ("shoes", "Shoes"),
  ("outerwear", "Outerwear"),
  ("bags", "Bags"),
  ("home", "Home"),
]

let categoryName = slug =>
  categories->Array.find(((found, _)) => found == slug)->Option.mapOr(slug, ((_, name)) => name)

/** Each category's products: name, price in cents, color. */
let catalog = [
  (
    "shoes",
    [
      ("Trail Runner", 12900, "green"),
      ("City Sneaker", 8900, "white"),
      ("Canvas Low", 5900, "blue"),
      ("Leather Boot", 18900, "brown"),
      ("Court Classic", 9900, "white"),
      ("Rain Boot", 7900, "black"),
      ("Slip-On Loafer", 11900, "brown"),
      ("Hiking Boot", 16900, "green"),
    ],
  ),
  (
    "outerwear",
    [
      ("Down Parka", 29900, "black"),
      ("Rain Shell", 14900, "blue"),
      ("Wool Overcoat", 34900, "grey"),
      ("Denim Jacket", 9900, "blue"),
      ("Fleece Pullover", 6900, "green"),
      ("Quilted Vest", 8900, "black"),
      ("Trench Coat", 24900, "brown"),
      ("Windbreaker", 7900, "white"),
    ],
  ),
  (
    "bags",
    [
      ("Weekender", 15900, "brown"),
      ("Day Pack", 7900, "black"),
      ("Tote", 4900, "white"),
      ("Messenger", 9900, "grey"),
      ("Duffel", 11900, "green"),
      ("Sling", 3900, "black"),
      ("Laptop Sleeve", 2900, "grey"),
      ("Roll-Top Pack", 12900, "blue"),
    ],
  ),
  (
    "home",
    [
      ("Linen Throw", 8900, "white"),
      ("Wool Blanket", 13900, "grey"),
      ("Ceramic Mug", 1900, "blue"),
      ("Pour-Over Set", 4900, "brown"),
      ("Cotton Towels", 3900, "white"),
      ("Table Lamp", 10900, "black"),
      ("Floor Cushion", 6900, "green"),
      ("Woven Basket", 3400, "brown"),
    ],
  ),
]

let colors = ["black", "blue", "brown", "green", "grey", "white"]

let hueOf = color =>
  switch color {
  | "black" => 230
  | "blue" => 210
  | "brown" => 25
  | "green" => 130
  | "grey" => 200
  | _ => 45
  }

let slugify = name => name->String.toLowerCase->String.replaceRegExp(/[^a-z0-9]+/g, "-")

let variantsOf = (category, id) =>
  switch category {
  | "shoes" =>
    ["7", "8", "9", "10", "11"]->Array.map(size => {
      sku: `${id}-${size}`,
      label: `Size ${size}`,
      priceDelta: 0,
    })
  | "outerwear" =>
    ["S", "M", "L", "XL"]->Array.map(size => {
      sku: `${id}-${size->String.toLowerCase}`,
      label: size,
      priceDelta: size == "XL" ? 1000 : 0,
    })
  | "home" => [
      {sku: `${id}-std`, label: "Standard", priceDelta: 0},
      {sku: `${id}-lg`, label: "Large", priceDelta: 2000},
    ]
  | _ => [{sku: `${id}-one`, label: "One size", priceDelta: 0}]
  }

let products: array<product> = catalog->Array.flatMapWithIndex(((category, items), categoryIndex) =>
  items->Array.mapWithIndex(((name, price, color), index) => {
    let number = categoryIndex * 8 + index + 1
    let id = `p${Int.toString(number)}`
    {
      summary: {
        id,
        slug: slugify(name),
        name,
        category,
        price,
        // Every third product is on sale.
        compareAt: mod(number, 3) == 0 ? Some(price + price / 4) : None,
        rating: 3.0 +. Int.toFloat(mod(number * 7, 21)) /. 10.0,
        hue: hueOf(color),
        color,
      },
      description: `The ${name}: made to last, in ${color}. One of our ${categoryName(
          category,
        )->String.toLowerCase} favourites.`,
      variants: variantsOf(category, id),
    }
  })
)

let all = () => products->Array.map(product => product.summary)
let find = id => products->Array.find(product => product.summary.id == id)
let findBySlug = slug => products->Array.find(product => product.summary.slug == slug)
let summary = id => find(id)->Option.map(product => product.summary)

/** The product a SKU is a variant of, and the variant. */
let findSku = sku =>
  products->Array.findMap(product =>
    product.variants
    ->Array.find(variant => variant.sku == sku)
    ->Option.map(variant => (product, variant))
  )

let inCategory = category => all()->Array.filter(summary => summary.category == category)

// Stock

let stock: Map.t<string, int> = Map.make()

let stockOf = sku => stock->Map.get(sku)->Option.getOr(0)

let productStock = id =>
  find(id)->Option.mapOr(0, product =>
    product.variants->Array.reduce(0, (total, variant) => total + stockOf(variant.sku))
  )

let setStock = (sku, count) => stock->Map.set(sku, count)

// Reviews

let reviewAuthors = ["Ada", "Grace", "Linus", "Barbara", "Alan", "Margaret", "Dennis", "Frances"]
let reviewTexts = [
  "Exactly as described.",
  "Great quality for the price.",
  "Runs a little small.",
  "Would buy again.",
  "The colour is lovely in person.",
  "Arrived quickly, well packed.",
  "Not for me, but well made.",
  "My favourite purchase this year.",
]

let reviewsOf = id => {
  let number = id->String.slice(~start=1)->Int.fromString->Option.getOr(0)
  Array.fromInitializer(~length=3 + mod(number * 5, 8), index => {
    id: `${id}-r${Int.toString(index + 1)}`,
    author: reviewAuthors->Array.getUnsafe(mod(number + index, 8)),
    stars: 1 + mod(number + index * 3, 5),
    text: reviewTexts->Array.getUnsafe(mod(number * 3 + index, 8)),
  })
}

// Queries the pages make

let deals = () => all()->Array.filter(summary => summary.compareAt->Option.isSome)
let featured = () => ["p1", "p10", "p17", "p28", "p4", "p20"]->Array.filterMap(summary)

/** Bought with `id`: others from its category, then one from the next. */
let alsoBought = id =>
  switch summary(id) {
  | Some(product) =>
    let same =
      inCategory(product.category)
      ->Array.filter(other => other.id != id)
      ->Array.slice(~start=0, ~end=3)
    let next = all()->Array.find(other => other.category != product.category)
    [...same, ...next->Option.mapOr([], other => [other])]
  | None => []
  }

let search = query => {
  let query = query->String.trim->String.toLowerCase
  query == ""
    ? []
    : all()->Array.filter(summary =>
        summary.name->String.toLowerCase->String.includes(query) ||
        summary.category->String.includes(query) ||
        summary.color == query
      )
}

type sort = Featured | PriceLow | PriceHigh | Rating

let sortOf = value =>
  switch value {
  | Some("price-asc") => PriceLow
  | Some("price-desc") => PriceHigh
  | Some("rating") => Rating
  | _ => Featured
  }

let sortValue = sort =>
  switch sort {
  | Featured => "featured"
  | PriceLow => "price-asc"
  | PriceHigh => "price-desc"
  | Rating => "rating"
  }

/** A category page's filters, from its query string. */
type filters = {
  colors: array<string>,
  low: option<int>,
  high: option<int>,
  inStock: bool,
  sort: sort,
}

let noFilters = {colors: [], low: None, high: None, inStock: false, sort: Featured}

let matches = (filters, summary) =>
  (filters.colors == [] || filters.colors->Array.includes(summary.color)) &&
  filters.low->Option.mapOr(true, low => summary.price >= low * 100) &&
  filters.high->Option.mapOr(true, high => summary.price <= high * 100) &&
  (!filters.inStock || productStock(summary.id) > 0)

let sorted = (items, sort) =>
  switch sort {
  | Featured => items
  | PriceLow => items->Array.toSorted((a, b) => Int.toFloat(a.price - b.price))
  | PriceHigh => items->Array.toSorted((a, b) => Int.toFloat(b.price - a.price))
  | Rating => items->Array.toSorted((a, b) => b.rating -. a.rating)
  }

let query = (category, filters) =>
  inCategory(category)->Array.filter(summary => matches(filters, summary))->sorted(filters.sort)

/** The filters a category page shows: what its products vary in, with counts. */
let facets = (category, filters) => {
  let items = inCategory(category)
  let prices = items->Array.map(summary => summary.price / 100)
  let min = prices->Array.reduce(100000, (a, b) => a < b ? a : b)
  let max = prices->Array.reduce(0, (a, b) => a > b ? a : b) + 1
  [
    Choices({
      name: "color",
      label: "Colour",
      options: colors->Array.filterMap(color => {
        let count = items->Array.filter(summary => summary.color == color)->Array.length
        count > 0 ? Some((color, count)) : None
      }),
      selected: filters.colors,
    }),
    Range({
      name: "price",
      label: "Price",
      min,
      max,
      low: filters.low->Option.getOr(min),
      high: filters.high->Option.getOr(max),
    }),
    Toggle({name: "instock", label: "In stock only", on: filters.inStock}),
  ]
}

// Users and orders

type user = {name: string, wishlist: Set.t<string>, orders: array<string>}

let users: Map.t<string, user> = Map.make()

let user = name =>
  switch users->Map.get(name) {
  | Some(user) => user
  | None =>
    let user = {name, wishlist: Set.make(), orders: []}
    users->Map.set(name, user)
    user
  }

type storedOrder = {
  order: order,
  /** When it was placed (`Date.now`). */
  placedAt: float,
  /** Its status, when the tests set it (otherwise it follows the clock). */
  mutable setStatus: option<orderStatus>,
}

let orders: Map.t<string, storedOrder> = Map.make()
let nextOrder = ref(1001)

let statusOf = stored =>
  switch stored.setStatus {
  | Some(status) => status
  | None =>
    switch Float.toInt((Date.now() -. stored.placedAt) /. 4000.0) {
    | 0 => Placed
    | 1 => Packed
    | 2 => Shipped
    | _ => Delivered
    }
  }

let findOrder = id =>
  orders->Map.get(id)->Option.map(stored => {...stored.order, status: statusOf(stored)})

/**
Places an order for `lines`, taking them out of stock, or says which SKUs there aren't enough of
(taking nothing).
*/
let placeOrder = (lines: array<cartLine>, ~name, ~total, ~manualStatus) => {
  let short =
    lines->Array.filter(line => stockOf(line.sku) < line.quantity)->Array.map(line => line.sku)
  if short != [] {
    Error(short)
  } else {
    lines->Array.forEach(line => setStock(line.sku, stockOf(line.sku) - line.quantity))
    let id = `o${Int.toString(nextOrder.contents)}`
    nextOrder := nextOrder.contents + 1
    orders->Map.set(
      id,
      {
        order: {id, lines, total, status: Placed, name},
        placedAt: Date.now(),
        setStatus: manualStatus ? Some(Placed) : None,
      },
    )
    user(name).orders->Array.push(id)
    Ok(id)
  }
}

let advanceOrder = id =>
  orders
  ->Map.get(id)
  ->Option.forEach(stored =>
    stored.setStatus = Some(
      switch statusOf(stored) {
      | Placed => Packed
      | Packed => Shipped
      | Shipped | Delivered => Delivered
      },
    )
  )

/** Everything as it started: every SKU's stock (a few short or sold out), no users, no orders. */
let seed = () => {
  stock->Map.clear
  products->Array.forEach(product =>
    product.variants->Array.forEachWithIndex((variant, index) => {
      let number = product.summary.id->String.slice(~start=1)->Int.fromString->Option.getOr(0)
      setStock(
        variant.sku,
        switch mod(number + index, 7) {
        | 0 => 0
        | 1 => 1
        | _ => 5
        },
      )
    })
  )
  users->Map.clear
  orders->Map.clear
  nextOrder := 1001
}

seed()
