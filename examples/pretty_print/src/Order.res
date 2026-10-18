/***
A tour of the rest of what the PPX handles: optional fields, built-in
containers, tuples, polymorphic variants, types from other modules, function
types, and opting a field out.
*/

@prettyPrint
type customer = {
  name: string,
  /** An optional field: printed when set, left out when not. */
  email?: string,
}

@prettyPrint
type lineItem = {
  sku: string,
  quantity: int,
  /** A tuple. */
  price: (float, [#usd | #eur]),
}

/** A type alias, here of a polymorphic variant. */
@prettyPrint
type status = [#pending | #shipped(string) | #returned(string, int)]

@prettyPrint
type t = {
  id: bigint,
  customer: customer,
  items: array<lineItem>,
  status: status,
  notes: option<string>,
  stockBySku: dict<int>,
  payment: result<unit, string>,
  /** A type from another module: uses `Geometry.point_toDoc`. */
  shipTo: Geometry.point,
  /** Likewise, with a type argument: uses `Tree.t_toDoc`. */
  history: Tree.t<status>,
  /** Functions print as `<fun>`. */
  onChange: status => unit,
  /**
  `Date.t` has no `t_toDoc`, so the PPX can't derive a printer for it.
  `@prettyPrint.opaque` prints the field as `<opaque>` instead.
  */
  placedAt: @prettyPrint.opaque Date.t,
}

/**
For a type the PPX can't handle, a printer can also be written by hand: any
`<type>_toDoc` function in scope is picked up, generated or not.
*/
module Timestamp = {
  type t = Date.t
  let t_toDoc = (date: t) => PrettyPrint.text(date->Date.toISOString)
}

@prettyPrint
type receipt = {
  order: t,
  printedAt: Timestamp.t,
}
