@@jsxConfig({version: 4, module_: "ResFiberDom.Jsx"})

/***
Drives the todo app the way a user would, in jsdom: typing, submitting, clicking.
*/

open Vitest

module Dom = ResFiberDom.Dom
module Client = ResFiberDom.Client

external toUnknown: 'a => unknown = "%identity"
external toBool: unknown => bool = "%identity"
@val @scope("localStorage") external clearStorage: unit => unit = "clear"

let mount = (~storageKey) => {
  let container = Dom.createElement(Dom.document, "div")
  Dom.appendChild(Dom.body(Dom.document), Dom.elementToNode(container))
  let root = Client.createRoot(container)
  Client.act(() => Client.render(root, <App storageKey />))
  (container, root)
}

let find = (container, selector) =>
  switch Nullable.toOption(Dom.querySelector(container, selector)) {
  | Some(element) => element
  | None => failwith(`nothing matches ${selector}`)
  }

let exists = (container, selector) => !Nullable.isNullable(Dom.querySelector(container, selector))

let titles = container =>
  Dom.querySelectorAll(container, "#todo-list li span")->Array.map(Dom.textContent)

let add = (container, title) => {
  let input = find(container, "#new-todo")
  Dom.setProperty(input, "value", toUnknown(title))
  Dom.dispatchEvent(input, Dom.Event.make("input", {bubbles: true}))
  Dom.dispatchEvent(
    find(container, "#new-todo-form"),
    Dom.Event.make("submit", {bubbles: true, cancelable: true}),
  )
}

let click = (container, selector) => Client.act(() => Dom.click(find(container, selector)))

let remaining = container => Dom.textContent(find(container, "#remaining"))

describe("Todo app", () => {
  beforeEach(() => clearStorage())

  test("focuses the new-todo input on mount", t => {
    let (container, root) = mount(~storageKey="focus")
    t
    ->expect(Dom.activeElement(Dom.document) === Nullable.make(find(container, "#new-todo")))
    ->Expect.toBe(true)
    Client.unmount(root)
  })

  test("adds trimmed todos, clears the input, and ignores blank ones", t => {
    let (container, root) = mount(~storageKey="add")
    add(container, "Write tests")
    add(container, "  Ship it  ")
    t->expect(Dom.getProperty(find(container, "#new-todo"), "value"))->Expect.toEqual(toUnknown(""))
    // Only whitespace: not added, and left in the input.
    add(container, "   ")
    t->expect(titles(container))->Expect.toEqual(["Write tests", "Ship it"])
    t
    ->expect(Dom.getProperty(find(container, "#new-todo"), "value"))
    ->Expect.toEqual(toUnknown("   "))
    t->expect(remaining(container))->Expect.toBe("2 items left")
    Client.unmount(root)
  })

  test("toggles, filters, removes and clears completed todos", t => {
    let (container, root) = mount(~storageKey="toggle")
    ["a", "b", "c"]->Array.forEach(add(container, _))
    click(container, "#toggle-2")
    t->expect(toBool(Dom.getProperty(find(container, "#toggle-2"), "checked")))->Expect.toBe(true)
    t
    ->expect(Dom.getAttribute(find(container, "#todo-2"), "class"))
    ->Expect.toEqual(Nullable.make("done"))
    t->expect(remaining(container))->Expect.toBe("2 items left")

    click(container, "#filter-active")
    t->expect(titles(container))->Expect.toEqual(["a", "c"])
    click(container, "#filter-completed")
    t->expect(titles(container))->Expect.toEqual(["b"])
    t
    ->expect(Dom.getAttribute(find(container, "#filter-completed"), "aria-pressed"))
    ->Expect.toEqual(Nullable.make("true"))
    click(container, "#filter-all")

    click(container, "#remove-1")
    t->expect(titles(container))->Expect.toEqual(["b", "c"])
    click(container, "#clear-completed")
    t->expect(titles(container))->Expect.toEqual(["c"])
    t->expect(remaining(container))->Expect.toBe("1 item left")
    t->expect(exists(container, "#clear-completed"))->Expect.toBe(false)
    Client.unmount(root)
  })

  test("keeps todos in localStorage across mounts", t => {
    let (container, root) = mount(~storageKey="persist")
    add(container, "remember me")
    click(container, "#toggle-1")
    Client.unmount(root)
    let (container, root) = mount(~storageKey="persist")
    t->expect(titles(container))->Expect.toEqual(["remember me"])
    t->expect(toBool(Dom.getProperty(find(container, "#toggle-1"), "checked")))->Expect.toBe(true)
    Client.unmount(root)
  })

  test("toggling one todo leaves the other items' nodes alone", t => {
    let (container, root) = mount(~storageKey="identity")
    ["a", "b"]->Array.forEach(add(container, _))
    let first = find(container, "#todo-1")
    click(container, "#toggle-2")
    t->expect(find(container, "#todo-1") === first)->Expect.toBe(true)
    Client.unmount(root)
  })
})
