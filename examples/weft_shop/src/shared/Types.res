/*** The data the server sends the client, and both sides share: types only (and their small helpers). */

/** Money, in cents of the store's own currency (US dollars). */
type cents = int

type currency = USD | EUR | GBP

/** A product as a card shows it. */
type summary = {
  id: string,
  slug: string,
  name: string,
  category: string,
  price: cents,
  /** The price before a sale, if it's on one. */
  compareAt: option<cents>,
  rating: float,
  /** The hue of its picture (there are no images: a gradient stands for one). */
  hue: int,
  color: string,
}

/** One of a product's variants (a size, say), which is what's bought. */
type variant = {sku: string, label: string, priceDelta: cents}

type product = {
  summary: summary,
  description: string,
  variants: array<variant>,
}

type review = {id: string, author: string, stars: int, text: string}

type cartLine = {
  sku: string,
  slug: string,
  name: string,
  variant: string,
  unitPrice: cents,
  quantity: int,
}

type cart = {
  lines: array<cartLine>,
  /** How many items, counting each line's quantity. */
  count: int,
  subtotal: cents,
  discount: cents,
  promo: option<string>,
  /** Goes up with every change, so the client can tell a newer cart from an older one. */
  version: int,
}

let emptyCart = {lines: [], count: 0, subtotal: 0, discount: 0, promo: None, version: 0}

type orderStatus = Placed | Packed | Shipped | Delivered

let statusLabel = status =>
  switch status {
  | Placed => "Placed"
  | Packed => "Packed"
  | Shipped => "Shipped"
  | Delivered => "Delivered"
  }

type order = {
  id: string,
  lines: array<cartLine>,
  total: cents,
  status: orderStatus,
  name: string,
}

/** A search box's suggestion. */
type suggestion = {slug: string, name: string, category: string}

/** A category page's filter, as the server decides to show it. */
type facet =
  | Choices({name: string, label: string, options: array<(string, int)>, selected: array<string>})
  | Range({name: string, label: string, min: int, max: int, low: int, high: int})
  | Toggle({name: string, label: string, on: bool})

/**
A product in a grid: its card, rendered on the server, with what the client filters it by. A page
of them is a grid's props, and more come from the `catalog.more` RPC.
*/
type gridItem = {key: string, name: string, card: Weft.Element.t}

/** How an order is delivered. */
type delivery = Standard | Express

let deliveryCost = delivery =>
  switch delivery {
  | Standard => 0
  | Express => 1500
  }

type checkout = {
  name: string,
  street: string,
  city: string,
  postcode: string,
  delivery: delivery,
  giftNote: option<string>,
}
