/***
Tests for the printers the `@prettyPrint` PPX generates for the types in this
package -- and so, in effect, for the PPX itself.
*/

open Vitest

let origin: Geometry.point = {x: 0.0, y: 0.0}

describe("@prettyPrint", () => {
  test("records", t => {
    t->expect(Geometry.point_prettyPrint({x: 1.5, y: -2.0}))->Expect.toBe("{x: 1.5, y: -2.0}")
  })

  test("variants", t => {
    t->expect(Geometry.color_prettyPrint(Red))->Expect.toBe("Red")
    t->expect(Geometry.color_prettyPrint(Rgb(1, 2, 3)))->Expect.toBe("Rgb(1, 2, 3)")
  })

  test("recursive variants with inline records", t => {
    t
    ->expect(Geometry.shape_prettyPrint(Colored(Green, Circle({center: origin, radius: 1.0}))))
    ->Expect.toBe("Colored(Green, Circle({center: {x: 0.0, y: 0.0}, radius: 1.0}))")
    t
    ->expect(Geometry.shape_prettyPrint(Polygon([origin, {x: 1.0, y: 1.0}])))
    ->Expect.toBe("Polygon([{x: 0.0, y: 0.0}, {x: 1.0, y: 1.0}])")
  })

  test("types with parameters take a printer per parameter", t => {
    t
    ->expect(Tree.t_prettyPrint(PrettyPrint.string, Tree.fromArray(["a"])))
    ->Expect.toBe(`Node({left: Leaf, value: "a", right: Leaf})`)
    t
    ->expect(
      Tree.t_prettyPrint(Geometry.point_toDoc, Node({left: Leaf, value: origin, right: Leaf})),
    )
    ->Expect.toBe("Node({left: Leaf, value: {x: 0.0, y: 0.0}, right: Leaf})")
  })

  test("optional fields are left out when unset", t => {
    t->expect(Order.customer_prettyPrint({name: "Ada"}))->Expect.toBe(`{name: "Ada"}`)
    t
    ->expect(Order.customer_prettyPrint({name: "Ada", email: "ada@example.com"}))
    ->Expect.toBe(`{name: "Ada", email: "ada@example.com"}`)
  })

  test("tuples and polymorphic variants", t => {
    t
    ->expect(Order.lineItem_prettyPrint({sku: "A", quantity: 2, price: (9.99, #usd)}))
    ->Expect.toBe(`{sku: "A", quantity: 2, price: (9.99, #usd)}`)
    t->expect(Order.status_prettyPrint(#pending))->Expect.toBe("#pending")
    t
    ->expect(Order.status_prettyPrint(#returned("damaged", 2)))
    ->Expect.toBe(`#returned("damaged", 2)`)
  })

  let order: Order.t = {
    id: 7n,
    customer: {name: "Ada"},
    items: [{sku: "A", quantity: 2, price: (9.99, #usd)}],
    status: #shipped("TRACK-42"),
    notes: Some("fragile"),
    stockBySku: dict{"A": 3},
    payment: Error("declined"),
    shipTo: origin,
    history: Leaf,
    onChange: _ => (),
    placedAt: Date.make(),
  }

  test("a value wider than the line is broken up, one element per line", t => {
    t
    ->expect(Order.t_prettyPrint(order))
    ->Expect.toBe(`{
  id: 7n,
  customer: {name: "Ada"},
  items: [{sku: "A", quantity: 2, price: (9.99, #usd)}],
  status: #shipped("TRACK-42"),
  notes: Some("fragile"),
  stockBySku: dict{"A": 3},
  payment: Error("declined"),
  shipTo: {x: 0.0, y: 0.0},
  history: Leaf,
  onChange: <fun>,
  placedAt: <opaque>,
}`)
  })

  test("<type>_toDoc renders at any width", t => {
    t
    ->expect(
      PrettyPrint.render(
        ~width=20,
        Order.lineItem_toDoc({sku: "A", quantity: 2, price: (9.99, #usd)}),
      ),
    )
    ->Expect.toBe(`{
  sku: "A",
  quantity: 2,
  price: (
    9.99,
    #usd,
  ),
}`)
  })

  test("hand-written <type>_toDoc printers are picked up", t => {
    let printedAt = Date.fromString("2026-01-02T03:04:05.000Z")

    t
    ->expect(
      Order.receipt_prettyPrint({order, printedAt})->String.endsWith(
        "  printedAt: 2026-01-02T03:04:05.000Z,\n}",
      ),
    )
    ->Expect.toBe(true)
  })
})
