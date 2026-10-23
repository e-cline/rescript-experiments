@@jsxConfig({version: 4, module_: "Jsx"})

/***
Pins down what ReScript's generic JSX transform hands `Weft.Jsx`: if a compiler upgrade changes
the shape of the calls (how keys, children or fragments arrive), these fail before the reconciler
misreads anything.
*/

open Vitest

external toUnknown: 'a => unknown = "%identity"
external fromUnknown: unknown => 'a = "%identity"

module Leaf = {
  @weft.component
  let make = (~label: string) => {
    ignore(label)
    Jsx.null
  }
}

module Box = {
  @weft.component
  let make = (~children: Jsx.element) => children
}

/** A provider-shaped module: what `<Ctx.Provider value>` needs (phase 2's `Context` relies on it). */
module Provider = {
  type props<'value, 'children> = {value: 'value, children: 'children}
  let make = (props: props<int, Jsx.element>) => props.children
}

let node = (element: Jsx.element): Element.node =>
  switch Element.classify(element) {
  | Node(node) => node
  | _ => failwith("expected a node element")
  }

let list = (element: Jsx.element): array<Jsx.element> =>
  switch Element.classify(element) {
  | List(children) => children
  | _ => failwith("expected a list element")
  }

describe("Jsx: the generic JSX transform's calls", () => {
  test("a component element holds its make function and props record", t => {
    let element = node(<Leaf label="a" />)
    t->expect(element.kind)->Expect.toBe(Component)
    t->expect(element.elementType === toUnknown(Leaf.make))->Expect.toBe(true)
    t->expect(element.key)->Expect.toEqual(Nullable.null)
    let props: Leaf.props<string> = fromUnknown(element.props)
    t->expect(props.label)->Expect.toBe("a")
  })

  test("a key arrives separately from props", t => {
    let element = node(<Leaf key="k" label="a" />)
    t->expect(element.key)->Expect.toEqual(Nullable.make("k"))
    let props: Leaf.props<string> = fromUnknown(element.props)
    t->expect(props.label)->Expect.toBe("a")
  })

  test("a single child is the element itself", t => {
    let child = node(
      Element.childrenOf(
        node(
          <Box>
            <Leaf label="a" />
          </Box>,
        ).props,
      ),
    )
    t->expect(child.elementType === toUnknown(Leaf.make))->Expect.toBe(true)
  })

  test("several children arrive as a plain array", t => {
    let children = list(
      Element.childrenOf(
        node(
          <Box>
            <Leaf label="a" />
            <Leaf label="b" />
          </Box>,
        ).props,
      ),
    )
    t->expect(Array.length(children))->Expect.toBe(2)
  })

  test("a fragment is a Fragment node whose children are its contents", t => {
    let element = node(
      <>
        <Leaf label="a" />
        {Jsx.string("text")}
      </>,
    )
    t->expect(element.kind)->Expect.toBe(Fragment)
    let children = list(Element.childrenOf(element.props))
    t->expect(Element.classify(children->Array.getUnsafe(1)))->Expect.toEqual(Element.Text("text"))
  })

  test("a keyed Fragment is a Fragment node with a key", t => {
    let element = node(
      <Jsx.Fragment key="f">
        <Leaf label="a" />
        <Leaf label="b" />
      </Jsx.Fragment>,
    )
    t->expect(element.kind)->Expect.toBe(Fragment)
    t->expect(element.key)->Expect.toEqual(Nullable.make("f"))
    t->expect(Array.length(list(Element.childrenOf(element.props))))->Expect.toBe(2)
  })

  test("a provider-shaped module gets value and children in its props", t => {
    let element = node(
      <Provider value=3>
        <Leaf label="a" />
      </Provider>,
    )
    let props: Provider.props<int, Jsx.element> = fromUnknown(element.props)
    t->expect(props.value)->Expect.toBe(3)
  })

  test("text, numbers, null and arrays classify as themselves", t => {
    t->expect(Element.classify(Jsx.string("hi")))->Expect.toEqual(Element.Text("hi"))
    t->expect(Element.classify(Jsx.int(42)))->Expect.toEqual(Element.Text("42"))
    t->expect(Element.classify(Jsx.float(1.5)))->Expect.toEqual(Element.Text("1.5"))
    t->expect(Element.classify(Jsx.null))->Expect.toEqual(Element.Empty)
    t->expect(Element.classify(Jsx.array([])))->Expect.toEqual(Element.List([]))
  })
})
