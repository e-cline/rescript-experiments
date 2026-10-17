@@jsxConfig({version: 4, module_: "TestJsx"})

open Vitest

let rendered = (element: TestJsx.element) => {
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, element)
  renderer
}

/** Renders `next` after `first`, returning the host operations the update alone performed. */
let opsForUpdate = (renderer, next: TestJsx.element) => {
  TestRenderer.clearOps(renderer)
  TestRenderer.render(renderer, next)
  TestRenderer.ops(renderer)
}

let uidOf = (renderer, id) =>
  switch TestRenderer.findById(renderer, id) {
  | Some(node) => TestRenderer.uid(node)
  | None => failwith(`no #${id}`)
  }

module KeyedList = {
  @jsx.component
  let make = (~items: array<string>) =>
    <ul id="list">
      {items
      ->Array.map(item => <li key=item id=item> {TestJsx.string(item)} </li>)
      ->TestJsx.array}
    </ul>
}

module Item = {
  @jsx.component
  let make = (~name: string) => <li id=name> {TestJsx.string(name)} </li>
}

/** Keyed components, each rendering one `<li>`: moves go through non-host fibers. */
module ComponentList = {
  @jsx.component
  let make = (~items: array<string>) =>
    <ul id="list"> {items->Array.map(item => <Item key=item name=item />)->TestJsx.array} </ul>
}

describe("Reconciler: mounting", () => {
  test("renders host elements and text", t => {
    let renderer = rendered(<div id="a" title="x"> {TestJsx.string("hi")} </div>)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<div id="a" title="x">hi</div>`)
  })

  test("builds a new tree off-screen and attaches it once", t => {
    let renderer = rendered(
      <div id="a">
        <span id="b"> {TestJsx.string("one")} </span>
        <span id="c"> {TestJsx.string("two")} </span>
      </div>,
    )
    t
    ->expect(TestRenderer.ops(renderer))
    ->Expect.toEqual([
      `create "one"`,
      "create span#b",
      `create "two"`,
      "create span#c",
      "create div#a",
      "append div#a to root",
    ])
  })

  test("renders components, fragments, numbers and nothing", t => {
    let renderer = rendered(
      <>
        <Item name="a" />
        {TestJsx.null}
        <>
          <Item name="b" />
          {TestJsx.int(3)}
        </>
      </>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<li id="a">a</li><li id="b">b</li>3`)
  })

  test("a component that renders nothing renders nothing", t => {
    module Nothing = {
      @jsx.component
      let make = () => TestJsx.null
    }
    let renderer = rendered(
      <div id="a">
        <Nothing />
      </div>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<div id="a"></div>`)
  })
})

describe("Reconciler: updating", () => {
  test("changed props update the existing node", t => {
    let renderer = rendered(<div id="a" title="x" />)
    let uid = uidOf(renderer, "a")
    t
    ->expect(opsForUpdate(renderer, <div id="a" title="y" className="c" />))
    ->Expect.toEqual(["update div#a {className, title}"])
    t->expect(uidOf(renderer, "a"))->Expect.toBe(uid)
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div className="c" id="a" title="y"></div>`)
  })

  test("changed text updates the text node", t => {
    let renderer = rendered(<div id="a"> {TestJsx.string("hi")} </div>)
    t
    ->expect(opsForUpdate(renderer, <div id="a"> {TestJsx.string("bye")} </div>))
    ->Expect.toEqual([`text "hi" -> "bye"`])
  })

  test("a different element type replaces the node", t => {
    let renderer = rendered(<div id="x" />)
    t
    ->expect(opsForUpdate(renderer, <span id="x" />))
    ->Expect.toEqual(["create span#x", "remove div#x", "append span#x to root"])
  })

  test("removing a subtree removes only its top host node", t => {
    let renderer = rendered(
      <div id="root">
        <ul id="gone">
          <li id="a" />
          <li id="b" />
        </ul>
      </div>,
    )
    t->expect(opsForUpdate(renderer, <div id="root" />))->Expect.toEqual(["remove ul#gone"])
  })

  test("an unchanged element does nothing on screen", t => {
    let element = <div id="a"> {TestJsx.string("hi")} </div>
    let renderer = rendered(element)
    t->expect(opsForUpdate(renderer, element))->Expect.toEqual([])
  })

  test("unmount removes everything", t => {
    let renderer = rendered(
      <>
        <div id="a" />
        <div id="b" />
      </>,
    )
    TestRenderer.clearOps(renderer)
    TestRenderer.unmount(renderer)
    t->expect(TestRenderer.ops(renderer))->Expect.toEqual(["remove div#a", "remove div#b"])
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("")
  })
})

describe("Reconciler: keyed children", () => {
  let cases = [
    (
      "moving the last to the front moves the others",
      ["a", "b", "c"],
      ["c", "a", "b"],
      // Moved nodes are placed last first, each before the one after it.
      ["append li#b to ul#list", "insert li#a before li#b"],
    ),
    (
      "moving the first to the end moves only it",
      ["a", "b", "c"],
      ["b", "c", "a"],
      ["append li#a to ul#list"],
    ),
    (
      "swapping two moves one",
      ["a", "b", "c", "d"],
      ["a", "c", "b", "d"],
      ["insert li#b before li#d"],
    ),
    (
      "inserting in the middle inserts before the next",
      ["a", "c"],
      ["a", "b", "c"],
      [`create "b"`, "create li#b", "insert li#b before li#c"],
    ),
    ("removing from the middle removes only it", ["a", "b", "c"], ["a", "c"], ["remove li#b"]),
    (
      "reversing",
      ["a", "b", "c"],
      ["c", "b", "a"],
      ["append li#a to ul#list", "insert li#b before li#a"],
    ),
  ]

  cases->Array.forEach(((name, before, after, expected)) => {
    test(
      name,
      t => {
        let renderer = rendered(<KeyedList items=before />)
        let uids = before->Array.map(uidOf(renderer, _))
        t->expect(opsForUpdate(renderer, <KeyedList items=after />))->Expect.toEqual(expected)
        t
        ->expect(TestRenderer.toString(renderer))
        ->Expect.toBe(
          `<ul id="list">${after
            ->Array.map(item => `<li id="${item}">${item}</li>`)
            ->Array.join("")}</ul>`,
        )
        // Every node that stayed is the same node.
        before->Array.forEachWithIndex(
          (item, index) =>
            if after->Array.includes(item) {
              t->expect(uidOf(renderer, item))->Expect.toBe(uids->Array.getUnsafe(index))
            },
        )
      },
    )

    test(
      `${name}, through components`,
      t => {
        let renderer = rendered(<ComponentList items=before />)
        t->expect(opsForUpdate(renderer, <ComponentList items=after />))->Expect.toEqual(expected)
        t
        ->expect(TestRenderer.toString(renderer))
        ->Expect.toBe(
          `<ul id="list">${after
            ->Array.map(item => `<li id="${item}">${item}</li>`)
            ->Array.join("")}</ul>`,
        )
      },
    )
  })

  test("unkeyed children match by position, around children that render nothing", t => {
    let view = (~showB) =>
      <ul id="list">
        <li id="a" />
        {showB ? <li id="b" /> : TestJsx.null}
        <li id="c" />
      </ul>
    let renderer = rendered(view(~showB=false))
    let c = uidOf(renderer, "c")
    t
    ->expect(opsForUpdate(renderer, view(~showB=true)))
    ->Expect.toEqual(["create li#b", "insert li#b before li#c"])
    t->expect(uidOf(renderer, "c"))->Expect.toBe(c)
    t->expect(opsForUpdate(renderer, view(~showB=false)))->Expect.toEqual(["remove li#b"])
  })

  test("a moved fragment moves all of its nodes", t => {
    let view = order =>
      <div id="root">
        {order
        ->Array.map(
          key =>
            <TestJsx.Fragment key>
              <i id={key ++ "1"} />
              <i id={key ++ "2"} />
            </TestJsx.Fragment>,
        )
        ->TestJsx.array}
      </div>
    let renderer = rendered(view(["a", "b"]))
    t
    ->expect(opsForUpdate(renderer, view(["b", "a"])))
    ->Expect.toEqual(["append i#a1 to div#root", "append i#a2 to div#root"])
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div id="root"><i id="b1"></i><i id="b2"></i><i id="a1"></i><i id="a2"></i></div>`)
  })
})
