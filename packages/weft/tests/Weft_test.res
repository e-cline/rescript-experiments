@@jsxConfig({version: 4, module_: "Weft.Jsx"})

open Vitest

module Counter = {
  @jsx.component
  let make = (~label: string) => {
    let (count, setCount) = Weft.Hooks.useState(() => 0)
    <button onClick={_ => setCount(c => c + 1)}>
      {Weft.Jsx.string(`${label}: `)}
      {Weft.Jsx.int(count)}
    </button>
  }
}

module Theme = {
  let context = Weft.Context.make("light")
  module Provider = {
    let make = Weft.Context.provider(context)
  }
}

module Themed = {
  @jsx.component
  let make = () => <span> {Weft.Jsx.string(Weft.Hooks.useContext(Theme.context))} </span>
}

module Memoed = {
  let make = Weft.Memo.memo(Themed.make)
}

let mount = (element: Weft.element) => {
  let container = Weft.Dom.createElement(Weft.Dom.document, "div")
  Weft.Dom.appendChild(Weft.Dom.body(Weft.Dom.document), Weft.Dom.elementToNode(container))
  let root = Weft.Client.createRoot(container)
  Weft.Client.act(() => Weft.Client.render(root, element))
  (container, root)
}

describe("Weft", () => {
  test("renders a component and updates it on events", t => {
    let (container, root) = mount(<Counter label="Clicks" />)
    t->expect(Weft.Dom.textContent(container))->Expect.toBe("Clicks: 0")
    let button = Weft.Dom.querySelector(container, "button")->Nullable.toOption->Option.getOrThrow
    Weft.Client.act(() => Weft.Dom.click(button))
    t->expect(Weft.Dom.textContent(container))->Expect.toBe("Clicks: 1")
    Weft.Client.unmount(root)
    t->expect(Weft.Dom.textContent(container))->Expect.toBe("")
  })

  test("provides context to a memoized component", t => {
    let (container, _) = mount(
      <Theme.Provider value="dark">
        <Memoed />
      </Theme.Provider>,
    )
    t->expect(Weft.Dom.textContent(container))->Expect.toBe("dark")
  })
})
