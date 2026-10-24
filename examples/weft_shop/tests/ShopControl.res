/***
What the tests do to the server, through `WeftTesting.callServer`: these run in the server's worker,
on the same modules the app uses. (Test-only, so the app itself has no test hooks beyond `Control`.)
*/

open Types

let reset = () => Control.reset()

// Latency
let release = gate => Latency.release(gate)
let releasePrefix = prefix => Latency.releasePrefix(prefix)
let releaseAll = () => Latency.releasePrefix("")
let fail = (gate, message) => Latency.fail(gate, message)
let heal = gate => Latency.heal(gate)
let hold = gate => Latency.hold(gate)
let waiting = () => Latency.waiting()
let abandoned = () => Latency.abandoned->Array.copy

// The catalog
let setStock = (sku, count) => Db.setStock(sku, count)
let stock = sku => Db.stockOf(sku)

// The CMS
let move = (page, id, index) => Cms.move(page, id, index)
let remove = (page, id) => Cms.remove(page, id)
let insertText = (page, id, index, title) => Cms.insertText(page, id, index, title)
let setHeroTitle = (page, title) => Cms.setHeroTitle(page, title)
/** Makes the live deals refresh every `seconds` (with the layouts as they started). */
let setLiveEvery = seconds => {
  Cms.liveEvery := seconds
  Cms.seed()
}

// Orders
let advanceOrder = id => Db.advanceOrder(id)
let orderStatus = id => Db.findOrder(id)->Option.mapOr("none", order => statusLabel(order.status))
let setPoll = ms => Pages.pollEvery := (ms > 0 ? Some(ms) : None)

// Sessions
let sessionCount = () => Session.sessions->Map.size

/** What the server keeps for the session `sid` names. */
let session = sid =>
  switch Session.sessions->Map.get(sid) {
  | Some(session) =>
    let cart = Session.cart(session)
    {
      "user": session.user->Option.getOr(""),
      "currency": Money.code(session.currency),
      "count": cart.count,
      "promo": session.promo->Option.getOr(""),
      "bucket": session.bucket,
      "viewed": session.viewed,
    }
  | None => {"user": "", "currency": "", "count": -1, "promo": "", "bucket": "", "viewed": []}
  }

/** Puts `quantity` of `sku` in the session's cart (as if added in another tab). */
let addToCart = (sid, sku, quantity) =>
  Session.sessions
  ->Map.get(sid)
  ->Option.forEach(session =>
    Session.setQuantity(session, sku, Session.quantityOf(session, sku) + quantity)
  )

let setBucket = (sid, bucket) =>
  Session.sessions->Map.get(sid)->Option.forEach(session => session.bucket = bucket)

let wishlist = name => Db.user(name).wishlist->Set.values->Iterator.toArray
let subscribers = () => ApiServer.subscribers->Set.values->Iterator.toArray
