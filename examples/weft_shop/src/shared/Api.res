/***
The RPCs the entrypoints call, declared here, in shared code: each one's ID, how its request goes
over the wire, and what's checked before it's sent (and again on the server). Their handlers are in
`ApiServer`, which only the server has.
*/

module Rpc = WeftServer.Rpc
module Codec = WeftServer.Rpc.Codec

open Types

/** What an RPC can say no with. */
type error =
  | NoSession
  | NotSignedIn
  | EmptyName
  | NameTooLong
  | NoSuchProduct
  | BadQuantity
  /** There aren't enough left of these SKUs. */
  | OutOfStock(array<string>)
  | UnknownPromo
  | ExpiredPromo
  | EmptyCart
  | InvalidEmail
  | MissingField(string)
  | InvalidPostcode

/** What to tell the shopper. */
let message = error =>
  switch error {
  | NoSession => "Your session has expired: reload the page."
  | NotSignedIn => "Sign in first."
  | EmptyName => "Enter a name."
  | NameTooLong => "That name is too long."
  | NoSuchProduct => "That product isn't sold any more."
  | BadQuantity => "Choose between 1 and 10."
  | OutOfStock(skus) => `Not enough left of ${skus->Array.join(", ")}.`
  | UnknownPromo => "That code isn't one of ours."
  | ExpiredPromo => "That code has expired."
  | EmptyCart => "Your cart is empty."
  | InvalidEmail => "That doesn't look like an email address."
  | MissingField(field) => `Fill in the ${field}.`
  | InvalidPostcode => "A postcode is five digits."
  }

/** What to tell the shopper when a call fails. */
let describe = (error: Rpc.error<error>) =>
  switch error {
  | Rejected(error) => message(error)
  | Invalid(_) => "The server couldn't read that: reload the page, and try again."
  | Failed(_) => "Something went wrong: try again."
  }

/** Nothing, on the wire. */
let nothing = Codec.custom(~encode=() => JSON.Null, ~decode=_ => Ok())

type line = {sku: string, quantity: int}

let line = Codec.object2(
  ("sku", Codec.string),
  ("quantity", Codec.int),
  (sku, quantity) => {sku, quantity},
  ({sku, quantity}) => (sku, quantity),
)

@weft.rpc({id: "cart.add"})
let addToCart: Rpc.t<line, line, cart, error> = Rpc.make(~request=line, ~check=({quantity}) =>
  quantity < 1 || quantity > 10 ? Error(BadQuantity) : Ok()
)

/** Sets a line's quantity (0 takes it out). */
@weft.rpc({id: "cart.setQuantity"})
let setQuantity: Rpc.t<line, line, cart, error> = Rpc.make(~request=line, ~check=({quantity}) =>
  quantity < 0 || quantity > 10 ? Error(BadQuantity) : Ok()
)

@weft.rpc({id: "cart.applyPromo"})
let applyPromo: Rpc.t<string, string, cart, error> = Rpc.makePrepared(
  ~request=Codec.string,
  ~prepare=async code =>
    switch code->String.trim->String.toUpperCase {
    | "" => Error(UnknownPromo)
    | code => Ok(code)
    },
)

let currency = Codec.variant(
  [Codec.constant("USD", USD), Codec.constant("EUR", EUR), Codec.constant("GBP", GBP)],
  ~encode=currency => Codec.tag(Money.code(currency)),
)

@weft.rpc({id: "prefs.setCurrency"})
let setCurrency: Rpc.t<currency, currency, unit, error> = Rpc.make(~request=currency)

@weft.rpc({id: "auth.signIn"})
let signIn: Rpc.t<string, string, string, error> = Rpc.makePrepared(
  ~request=Codec.string,
  ~prepare=async name =>
    switch String.trim(name) {
    | "" => Error(EmptyName)
    | name => Ok(name)
    },
  ~check=name =>
    name == "" ? Error(EmptyName) : String.length(name) > 40 ? Error(NameTooLong) : Ok(),
)

@weft.rpc({id: "auth.signOut"})
let signOut: Rpc.t<unit, unit, unit, error> = Rpc.make(~request=nothing)

/** Saves or unsaves a product. The response: whether it's saved now. */
@weft.rpc({id: "wishlist.toggle"})
let toggleWishlist: Rpc.t<string, string, bool, error> = Rpc.make(~request=Codec.string)

@weft.rpc({id: "search.suggest"})
let suggest: Rpc.t<string, string, array<suggestion>, error> = Rpc.make(~request=Codec.string)

type more = {
  /** The category's slug, or `""` for search results. */
  category: string,
  /** The page's query string (its filters, or the search). */
  query: string,
  page: int,
}

type morePage = {items: array<gridItem>, next: option<int>}

/** The next page of a grid: the cards themselves, rendered on the server. */
@weft.rpc({id: "catalog.more"})
let more: Rpc.t<more, more, morePage, error> = Rpc.make(
  ~request=Codec.object3(
    ("category", Codec.string),
    ("query", Codec.string),
    ("page", Codec.int),
    (category, query, page) => {category, query, page},
    ({category, query, page}) => (category, query, page),
  ),
  ~check=({page}) => page < 1 ? Error(BadQuantity) : Ok(),
)

let isEmail = email => /^[^@\s]+@[^@\s]+\.[^@\s]+$/->RegExp.test(email)

@weft.rpc({id: "newsletter.subscribe"})
let subscribe: Rpc.t<string, string, unit, error> = Rpc.makePrepared(
  ~request=Codec.string,
  ~prepare=async email => Ok(email->String.trim->String.toLowerCase),
  ~check=email => isEmail(email) ? Ok() : Error(InvalidEmail),
)

let delivery = Codec.variant(
  [Codec.constant("Standard", Standard), Codec.constant("Express", Express)],
  ~encode=delivery =>
    switch delivery {
    | Standard => Codec.tag("Standard")
    | Express => Codec.tag("Express")
    },
)

let trimmed = (details: checkout) => {
  name: String.trim(details.name),
  street: String.trim(details.street),
  city: String.trim(details.city),
  postcode: String.trim(details.postcode),
  delivery: details.delivery,
  giftNote: details.giftNote->Option.map(String.trim)->Option.filter(note => note != ""),
}

/** What's wrong with an address, if anything: the first field missing, then the postcode. */
let checkAddress = (details: checkout) =>
  switch [
    ("name", details.name),
    ("street", details.street),
    ("city", details.city),
    ("postcode", details.postcode),
  ]->Array.find(((_, value)) => value == "") {
  | Some((field, _)) => Error(MissingField(field))
  | None => /^[0-9]{5}$/->RegExp.test(details.postcode) ? Ok() : Error(InvalidPostcode)
  }

/** Places the order for what's in the cart. The response: the order's id. */
@weft.rpc({id: "checkout.placeOrder"})
let placeOrder: Rpc.t<checkout, checkout, string, error> = Rpc.makePrepared(
  ~request=Codec.object6(
    ("name", Codec.string),
    ("street", Codec.string),
    ("city", Codec.string),
    ("postcode", Codec.string),
    ("delivery", delivery),
    ("giftNote", Codec.option(Codec.string)),
    (name, street, city, postcode, delivery, giftNote) => {
      name,
      street,
      city,
      postcode,
      delivery,
      giftNote,
    },
    ({name, street, city, postcode, delivery, giftNote}) => (
      name,
      street,
      city,
      postcode,
      delivery,
      giftNote,
    ),
  ),
  ~prepare=async details => Ok(trimmed(details)),
  ~check=checkAddress,
)
