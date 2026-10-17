/***
Prints a few values with their generated printers. Run with `vp run demo`
(or, after a build, `node src/Demo.res.js`).
*/

let section = (title, output) => Console.log(`-- ${title}\n${output}\n`)

let origin: Geometry.point = {x: 0.0, y: 0.0}

section("a record", Geometry.point_prettyPrint(origin))

section(
  "nested variants",
  Geometry.shape_prettyPrint(Colored(Rgb(255, 128, 0), Circle({center: origin, radius: 2.5}))),
)

section(
  "a polymorphic type, given a printer for its parameter",
  Tree.t_prettyPrint(PrettyPrint.int, Tree.fromArray([1, 2, 3])),
)

let order: Order.t = {
  id: 9007199254740993n,
  customer: {name: "Ada Lovelace", email: "ada@example.com"},
  items: [
    {sku: "ENGINE-1", quantity: 1, price: (1700.0, #eur)},
    {sku: "CARD-25", quantity: 25, price: (0.5, #usd)},
  ],
  status: #shipped("TRACK-42"),
  notes: None,
  stockBySku: dict{"ENGINE-1": 0, "CARD-25": 975},
  payment: Ok(),
  shipTo: {x: 51.5, y: -0.1},
  history: Tree.fromArray([#pending, #shipped("TRACK-42")]),
  onChange: _ => (),
  placedAt: Date.fromString("1843-10-01T00:00:00.000Z"),
}

section("a value too wide for one line", Order.t_prettyPrint(order))

// `<type>_prettyPrint` always renders 80 columns wide. For another width,
// render the doc from `<type>_toDoc`.
section("the same value, 40 columns wide", PrettyPrint.render(~width=40, Order.t_toDoc(order)))

section(
  "a hand-written printer",
  Order.receipt_prettyPrint({order, printedAt: Date.fromString("1843-10-02T12:30:00.000Z")}),
)
