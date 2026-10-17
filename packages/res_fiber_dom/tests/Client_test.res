@@jsxConfig({version: 4, module_: "Jsx"})

open Vitest

module Hooks = ResFiber.Hooks

let makeContainer = () => {
  let container = Dom.createElement(Dom.document, "div")
  Dom.appendChild(Dom.body(Dom.document), Dom.elementToNode(container))
  container
}

let mount = (element: Jsx.element) => {
  let container = makeContainer()
  let root = Client.createRoot(container)
  Client.act(() => Client.render(root, element))
  (container, root)
}

let rerender = (root, element: Jsx.element) => Client.act(() => Client.render(root, element))

let find = (container, selector) =>
  switch Nullable.toOption(Dom.querySelector(container, selector)) {
  | Some(element) => element
  | None => failwith(`nothing matches ${selector}`)
  }

external toUnknown: 'a => unknown = "%identity"
external toString: unknown => string = "%identity"
external toBool: unknown => bool = "%identity"

let valueOf = element => toString(Dom.getProperty(element, "value"))

/** Types `text` into an input: sets its value and fires `input`, as a keystroke would. */
let typeInto = (input, text) => {
  Dom.setProperty(input, "value", toUnknown(text))
  Dom.dispatchEvent(input, Dom.Event.make("input", {bubbles: true}))
}

describe("Rendering", () => {
  test("creates elements, attributes and text", t => {
    let (container, _) = mount(
      <div id="a" className="box" title="t">
        <span> {Jsx.string("hi")} </span>
        {Jsx.int(3)}
      </div>,
    )
    t
    ->expect(Dom.innerHTML(container))
    ->Expect.toBe(`<div id="a" class="box" title="t"><span>hi</span>3</div>`)
  })

  test("createRoot empties the container", t => {
    let container = makeContainer()
    Dom.setTextContent(container, "old content")
    let root = Client.createRoot(container)
    Client.act(() => Client.render(root, <p> {Jsx.string("new")} </p>))
    t->expect(Dom.innerHTML(container))->Expect.toBe("<p>new</p>")
  })

  testAsync("render outside act happens in a microtask", async t => {
    let container = makeContainer()
    let root = Client.createRoot(container)
    Client.render(root, <p> {Jsx.string("later")} </p>)
    t->expect(Dom.innerHTML(container))->Expect.toBe("")
    await Promise.resolve()
    t->expect(Dom.innerHTML(container))->Expect.toBe("<p>later</p>")
  })

  test("updates change the existing nodes", t => {
    let (container, root) = mount(<p id="p" title="one"> {Jsx.string("before")} </p>)
    let paragraph = find(container, "#p")
    rerender(root, <p id="p" className="c"> {Jsx.string("after")} </p>)
    t->expect(find(container, "#p") === paragraph)->Expect.toBe(true)
    t->expect(Dom.innerHTML(container))->Expect.toBe(`<p id="p" class="c">after</p>`)
  })

  test("boolean props add and remove attributes", t => {
    let (container, root) = mount(<button id="b" disabled=true hidden=false />)
    let button = find(container, "#b")
    t->expect(Dom.getAttribute(button, "disabled"))->Expect.toEqual(Nullable.make(""))
    t->expect(Dom.getAttribute(button, "hidden"))->Expect.toEqual(Nullable.null)
    rerender(root, <button id="b" disabled=false hidden=true />)
    t->expect(Dom.getAttribute(button, "disabled"))->Expect.toEqual(Nullable.null)
    t->expect(Dom.getAttribute(button, "hidden"))->Expect.toEqual(Nullable.make(""))
  })

  test("renamed attributes: className, htmlFor, type_, aria-*, data-*", t => {
    let (container, _) = mount(
      <label className="l" htmlFor="x" ariaLabel="name" dataTestId="t">
        <input type_="checkbox" />
      </label>,
    )
    let label = find(container, "label")
    t
    ->expect(
      ["class", "for", "aria-label", "data-testid"]->Array.map(
        name => Dom.getAttribute(label, name)->Nullable.toOption,
      ),
    )
    ->Expect.toEqual([Some("l"), Some("x"), Some("name"), Some("t")])
    t
    ->expect(Dom.getAttribute(find(container, "input"), "type"))
    ->Expect.toEqual(Nullable.make("checkbox"))
  })

  test("style sets, changes and removes only what changed", t => {
    let (container, root) = mount(
      <div id="s" style={dict{"color": "red", "background-color": "blue"}} />,
    )
    let style = Dom.style(find(container, "#s"))
    t->expect(Dom.getStyle(style, "color"))->Expect.toBe("red")
    t->expect(Dom.getStyle(style, "backgroundColor"))->Expect.toBe("blue")
    rerender(root, <div id="s" style={dict{"color": "green", "marginTop": "4px"}} />)
    t->expect(Dom.getStyle(style, "color"))->Expect.toBe("green")
    t->expect(Dom.getStyle(style, "backgroundColor"))->Expect.toBe("")
    t->expect(Dom.getStyle(style, "marginTop"))->Expect.toBe("4px")
  })

  test("keyed moves keep the same DOM nodes", t => {
    let list = items =>
      <ul>
        {items->Array.map(item => <li key=item id=item> {Jsx.string(item)} </li>)->Jsx.array}
      </ul>
    let (container, root) = mount(list(["a", "b", "c"]))
    let a = find(container, "#a")
    let c = find(container, "#c")
    rerender(root, list(["c", "a"]))
    t->expect(Dom.innerHTML(container))->Expect.toBe(`<ul><li id="c">c</li><li id="a">a</li></ul>`)
    t
    ->expect((find(container, "#a") === a, find(container, "#c") === c))
    ->Expect.toEqual((true, true))
  })

  test("unmount empties the container and runs cleanups", t => {
    let cleaned = ref(false)
    module Cleans = {
      @jsx.component
      let make = () => {
        Hooks.useEffect0(() => Some(() => cleaned := true))
        <p />
      }
    }
    let (container, root) = mount(<Cleans />)
    Client.unmount(root)
    t->expect(Dom.innerHTML(container))->Expect.toBe("")
    t->expect(cleaned.contents)->Expect.toBe(true)
  })
})

module Counter = {
  @jsx.component
  let make = () => {
    let (count, setCount) = Hooks.useState(() => 0)
    <button id="count" onClick={_ => setCount(c => c + 1)}> {Jsx.int(count)} </button>
  }
}

describe("Events", () => {
  test("a handler's update renders before the event returns", t => {
    let (container, _) = mount(<Counter />)
    let button = find(container, "#count")
    Dom.click(button)
    Dom.click(button)
    t->expect(Dom.textContent(button))->Expect.toBe("2")
  })

  test("swapping a handler calls the new one; removing it stops calls", t => {
    let calls = []
    let view = (handler: option<string>) =>
      <button id="b" onClick=?{handler->Option.map(name => _ => calls->Array.push(name))} />
    let (container, root) = mount(view(Some("first")))
    let button = find(container, "#b")
    Dom.click(button)
    rerender(root, view(Some("second")))
    Dom.click(button)
    rerender(root, view(None))
    Dom.click(button)
    t->expect(calls)->Expect.toEqual(["first", "second"])
  })

  test("a controlled input shows what its state makes of the input", t => {
    module Upper = {
      @jsx.component
      let make = () => {
        let (value, setValue) = Hooks.useState(() => "")
        <input
          id="in"
          value
          onInput={event => setValue(_ => event->Dom.Event.targetValue->String.toUpperCase)}
        />
      }
    }
    let (container, _) = mount(<Upper />)
    let input = find(container, "#in")
    typeInto(input, "abc")
    t->expect(valueOf(input))->Expect.toBe("ABC")
  })

  test("a controlled input its state ignores keeps its value", t => {
    let (container, _) = mount(<input id="in" value="fixed" onInput={_ => ()} />)
    let input = find(container, "#in")
    typeInto(input, "typed")
    t->expect(valueOf(input))->Expect.toBe("fixed")
  })

  test("a controlled checkbox follows its state", t => {
    module Check = {
      @jsx.component
      let make = () => {
        let (checked, setChecked) = Hooks.useState(() => false)
        <input id="c" type_="checkbox" checked onChange={_ => setChecked(c => !c)} />
      }
    }
    let (container, _) = mount(<Check />)
    let box = find(container, "#c")
    Dom.click(box)
    t->expect(toBool(Dom.getProperty(box, "checked")))->Expect.toBe(true)
    Dom.click(box)
    t->expect(toBool(Dom.getProperty(box, "checked")))->Expect.toBe(false)
  })
})

describe("Refs and focus", () => {
  test("a ref gets the element, in time for an effect to focus it", t => {
    module AutoFocus = {
      @jsx.component
      let make = () => {
        let input = Hooks.useRef(Nullable.null)
        Hooks.useEffect0(
          () => {
            input.current->Nullable.forEach(Dom.focus)
            None
          },
        )
        <input id="focus-me" ref=input />
      }
    }
    let (container, _) = mount(<AutoFocus />)
    t
    ->expect(Dom.activeElement(Dom.document) === Nullable.make(find(container, "#focus-me")))
    ->Expect.toBe(true)
  })

  test("a focused element keeps focus when a reorder moves it", t => {
    let list = items =>
      <div> {items->Array.map(item => <input key=item id=item />)->Jsx.array} </div>
    let (container, root) = mount(list(["a", "b", "c"]))
    let a = find(container, "#a")
    Dom.focus(a)
    rerender(root, list(["b", "c", "a"]))
    t->expect(Dom.activeElement(Dom.document) === Nullable.make(a))->Expect.toBe(true)
  })
})

describe("Transitions in the page", () => {
  testAsync("a transition from an event renders in a later task", async t => {
    module Tabs = {
      @jsx.component
      let make = () => {
        let (tab, setTab) = Hooks.useState(() => "home")
        <button id="tab" onClick={_ => ResFiber.Transition.start(() => setTab(_ => "settings"))}>
          {Jsx.string(tab)}
        </button>
      }
    }
    let (container, _) = mount(<Tabs />)
    let button = find(container, "#tab")
    Dom.click(button)
    t->expect(Dom.textContent(button))->Expect.toBe("home")
    await Promise.make((resolve, _) => setTimeout(() => resolve(), 20)->ignore)
    t->expect(Dom.textContent(button))->Expect.toBe("settings")
  })
})

describe("Portals", () => {
  test("render into another element, handle events, and leave with their owner", t => {
    let layer = makeContainer()
    let clicks = ref(0)
    let view = (~open_) =>
      <main id="main">
        {open_
          ? <Portal container=layer>
              <button id="in-portal" onClick={_ => clicks := clicks.contents + 1} />
            </Portal>
          : Jsx.null}
      </main>
    let (container, root) = mount(view(~open_=true))
    t->expect(Dom.innerHTML(container))->Expect.toBe(`<main id="main"></main>`)
    t->expect(Dom.innerHTML(layer))->Expect.toBe(`<button id="in-portal"></button>`)
    Dom.click(find(layer, "#in-portal"))
    t->expect(clicks.contents)->Expect.toBe(1)
    rerender(root, view(~open_=false))
    t->expect(Dom.innerHTML(layer))->Expect.toBe("")
  })
})
