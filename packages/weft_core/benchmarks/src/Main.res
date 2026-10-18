@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
Benchmarks of the reconciler driving a list of rows, after the operations of the well-known
JS framework benchmark: mounting, replacing every row's text, rendering again with nothing changed,
one row updating its own state, reversing, swapping two rows, removing one, a context change read by
every row, and rendering in a transition. Each runs at 1,000 and 10,000 rows, so a cost that grows
faster than the list does stands out.

The host is `BenchHost`: in-memory nodes with constant-time child operations, so the times are the
reconciler's. Every benchmark toggles between two states (or mounts and then unmounts), so that
each call does the same work as the last, and checks the result once while setting up.
*/

open Benchmarking
module Hooks = WeftCore.Hooks
module TestJsx = WeftCore.TestJsx
module Renderer = WeftCore.Reconciler.MakeWithScheduler(BenchHost, BenchScheduler)

type row = {id: string, label: string}

let makeRows = (count: int, ~generation: int): array<row> =>
  Array.fromInitializer(~length=count, i => {
    id: Int.toString(i),
    label: `row ${Int.toString(i)}, generation ${Int.toString(generation)}`,
  })

module Row = {
  @jsx.component
  let make = (~row: row) => <li id=row.id> {TestJsx.string(row.label)} </li>
}

module List = {
  @jsx.component
  let make = (~rows: array<row>) =>
    <ul> {rows->Array.map(row => <Row key=row.id row />)->TestJsx.array} </ul>
}

let mountRoot = () => {
  let container = BenchHost.makeNode(~tag="root", ~props={}, ~text="")
  (Renderer.createRoot(container), container)
}

let renderSync = (root, element: TestJsx.element) =>
  Renderer.flushSync(() => Renderer.render(root, element))

let check = (condition: bool, message: string) =>
  if !condition {
    JsError.throwWithMessage(`fiber benchmark setup: ${message}`)
  }

/** The list's rows, in order, as ids. */
let rowIds = (container: BenchHost.node) => {
  let ids = []
  let ul: BenchHost.node = container.first->Option.getUnsafe
  let row = ref(ul.first)
  while Option.isSome(row.contents) {
    let li = Option.getUnsafe(row.contents)
    ids->Array.push(li.props.id->Option.getOr("?"))
    row := li.next
  }
  ids
}

/** Toggles between `a` and `b`, returning the one switched to. */
let toggler = (a, b) => {
  let showingA = ref(true)
  () => {
    showingA := !showingA.contents
    showingA.contents ? a : b
  }
}

/** A list mounted with `rows`, and a measure that alternates rendering `other` and `rows`. */
let alternating = (rows: array<row>, other: array<row>, ~expect: BenchHost.node => unit) => {
  let (root, container) = mountRoot()
  renderSync(root, <List rows />)
  let next = toggler(rows, other)
  let measure = () => renderSync(root, <List rows={next()} />)
  measure()
  expect(container)
  measure()
  {Mitata.measure: measure}
}

let setters: array<(int => int) => unit> = []

module StatefulRow = {
  @jsx.component
  let make = (~row: row) => {
    let (count, setCount) = Hooks.useState(() => 0)
    setters->Array.setUnsafe(Int.fromString(row.id)->Option.getUnsafe, setCount)
    <li id=row.id> {TestJsx.string(`${row.label}: ${Int.toString(count)}`)} </li>
  }
}

module StatefulList = {
  @jsx.component
  let make = (~rows: array<row>) =>
    <ul> {rows->Array.map(row => <StatefulRow key=row.id row />)->TestJsx.array} </ul>
}

module Theme = {
  let context = WeftCore.Context.make("light")
  module Provider = {
    let make = WeftCore.Context.provider(context)
  }
}

module ThemedRow = {
  @jsx.component
  let make = WeftCore.Memo.memo((~row: row) => {
    let theme = Hooks.useContext(Theme.context)
    <li id=row.id className=theme> {TestJsx.string(row.label)} </li>
  })
}

module ThemedList = {
  @jsx.component
  let make = WeftCore.Memo.memo((~rows: array<row>) =>
    <ul> {rows->Array.map(row => <ThemedRow key=row.id row />)->TestJsx.array} </ul>
  )
}

let benchListOfSize = (size: int) => {
  let n = Int.toString(size)
  let middle = size / 2

  Mitata.group(`a list of ${n} rows`, () => {
    Mitata.benchWithSetup(`mount, then unmount, ${n} rows`, () => {
      let rows = makeRows(size, ~generation=0)
      let (root, container) = mountRoot()
      renderSync(root, <List rows />)
      check(BenchHost.count(container) == 1 + 2 * size, "mount")
      renderSync(root, TestJsx.null)
      check(BenchHost.count(container) == 0, "unmount")
      {
        measure: () => {
          renderSync(root, <List rows />)
          renderSync(root, TestJsx.null)
        },
      }
    })->ignore

    Mitata.benchWithSetup(`replace the text of all ${n} rows`, () =>
      alternating(
        makeRows(size, ~generation=0),
        makeRows(size, ~generation=1),
        ~expect=container => {
          let ul: BenchHost.node = container.first->Option.getUnsafe
          let li: BenchHost.node = ul.first->Option.getUnsafe
          let text: BenchHost.node = li.first->Option.getUnsafe
          check(text.text == "row 0, generation 1", "replace")
        },
      )
    )->ignore

    Mitata.benchWithSetup(`render ${n} rows again, nothing changed`, () => {
      let rows = makeRows(size, ~generation=0)
      alternating(
        rows,
        rows,
        ~expect=container => check(Array.length(rowIds(container)) == size, "rerender"),
      )
    })->ignore

    Mitata.benchWithSetup(`one of ${n} rows updates its own state`, () => {
      let rows = makeRows(size, ~generation=0)
      let (root, container) = mountRoot()
      renderSync(root, <StatefulList rows />)
      let setCount = setters->Array.getUnsafe(middle)
      let measure = () => Renderer.flushSync(() => setCount(c => c + 1))
      measure()
      let ul: BenchHost.node = container.first->Option.getUnsafe
      let li: ref<BenchHost.node> = ref(ul.first->Option.getUnsafe)
      for _ in 1 to middle {
        li := li.contents.next->Option.getUnsafe
      }
      let text: BenchHost.node = li.contents.first->Option.getUnsafe
      check(text.text->String.endsWith(": 1"), "own state")
      {measure: measure}
    })->ignore

    Mitata.benchWithSetup(`reverse ${n} keyed rows`, () => {
      let rows = makeRows(size, ~generation=0)
      alternating(
        rows,
        rows->Array.toReversed,
        ~expect=container =>
          check(rowIds(container)->Array.getUnsafe(0) == Int.toString(size - 1), "reverse"),
      )
    })->ignore

    Mitata.benchWithSetup(`swap two of ${n} keyed rows`, () => {
      let rows = makeRows(size, ~generation=0)
      let swapped = rows->Array.copy
      swapped->Array.setUnsafe(1, rows->Array.getUnsafe(size - 2))
      swapped->Array.setUnsafe(size - 2, rows->Array.getUnsafe(1))
      alternating(
        rows,
        swapped,
        ~expect=container =>
          check(rowIds(container)->Array.getUnsafe(1) == Int.toString(size - 2), "swap"),
      )
    })->ignore

    Mitata.benchWithSetup(`remove, then restore, one of ${n} keyed rows`, () => {
      let rows = makeRows(size, ~generation=0)
      alternating(
        rows,
        rows->Array.filterWithIndex((_, i) => i != middle),
        ~expect=container => check(Array.length(rowIds(container)) == size - 1, "remove"),
      )
    })->ignore

    Mitata.benchWithSetup(`change a context read by ${n} memoized rows`, () => {
      let rows = makeRows(size, ~generation=0)
      let (root, container) = mountRoot()
      // The same list element every time: only the context change reaches the rows.
      let list = <ThemedList rows />
      let next = toggler("light", "dark")
      let measure = () => renderSync(root, <Theme.Provider value={next()}> list </Theme.Provider>)
      measure()
      let ul: BenchHost.node = container.first->Option.getUnsafe
      let last: BenchHost.node = ul.last->Option.getUnsafe
      check(last.props.className == Some("dark"), "context")
      {measure: measure}
    })->ignore

    Mitata.benchWithSetup(`render ${n} rows in a transition, yielding every 100 units`, () => {
      let (root, container) = mountRoot()
      renderSync(root, <List rows={makeRows(size, ~generation=0)} />)
      let next = toggler(makeRows(size, ~generation=0), makeRows(size, ~generation=1))
      let measure = () => {
        WeftCore.Transition.start(() => Renderer.render(root, <List rows={next()} />))
        Mitata.doNotOptimize(BenchScheduler.flushAll())
      }
      WeftCore.Transition.start(() => Renderer.render(root, <List rows={next()} />))
      check(BenchScheduler.flushAll() > size / 100, "transition yields")
      check(Array.length(rowIds(container)) == size, "transition")
      {measure: measure}
    })->ignore
  })
}

[1_000, 10_000]->Array.forEach(benchListOfSize)

(await Runner.main())->ignore
