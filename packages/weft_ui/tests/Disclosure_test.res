/*** Tabs, Accordion, Collapsible and Combobox: their ARIA, their state and the keyboard. */
open Vitest
open Support
module Jsx = WeftDom.Jsx

Testing.installJsdomShims()

let focused = element => activeElement() == Some(element)

afterEach(() => Dom.setTextContent(Dom.body(Dom.document), ""))

describe("Tabs", () => {
  let tabs = (~activation=?, ~value=?, ~onValueChange=?, ()) =>
    mount(
      <Tabs.Root defaultValue="a" ?activation ?value ?onValueChange>
        <Tabs.List label="Product">
          <Tabs.Tab value="a"> {text("Details")} </Tabs.Tab>
          <Tabs.Tab value="b" disabled=true> {text("Sizes")} </Tabs.Tab>
          <Tabs.Tab value="c"> {text("Reviews")} </Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="a"> {text("About it")} </Tabs.Panel>
        <Tabs.Panel value="b"> {text("S, M, L")} </Tabs.Panel>
        <Tabs.Panel value="c"> {text("5 stars")} </Tabs.Panel>
      </Tabs.Root>,
    )
  let selected = container =>
    findAll(container, "[role=tab]")->Array.map(tab => attribute(tab, "aria-selected"))
  let shown = container =>
    findAll(container, "[role=tabpanel]")->Array.map(panel => attribute(panel, "hidden") == None)

  test(
    "tabs control their panels, which they label; the selected one shows, and is the Tab stop",
    t => {
      let container = tabs()
      let tablist = find(container, "[role=tablist]")
      t->expect(attribute(tablist, "aria-label"))->Expect.toEqual(Some("Product"))
      let all = findAll(container, "[role=tab]")
      let panels = findAll(container, "[role=tabpanel]")
      all->Array.forEachWithIndex(
        (tab, index) => {
          let panel = panels->Array.getUnsafe(index)
          t->expect(attribute(tab, "aria-controls"))->Expect.toEqual(attribute(panel, "id"))
          t->expect(attribute(panel, "aria-labelledby"))->Expect.toEqual(attribute(tab, "id"))
        },
      )
      t->expect(selected(container))->Expect.toEqual([Some("true"), Some("false"), Some("false")])
      t->expect(shown(container))->Expect.toEqual([true, false, false])
      t
      ->expect(all->Array.map(tab => attribute(tab, "tabindex")))
      ->Expect.toEqual([Some("0"), Some("-1"), Some("-1")])
    },
  )

  test("the arrow keys move and select, past disabled tabs, wrapping; a click selects", t => {
    let container = tabs()
    let all = findAll(container, "[role=tab]")
    let first = all->Array.getUnsafe(0)
    focus(first)
    keyDown(first, "ArrowRight")->ignore
    t->expect(focused(all->Array.getUnsafe(2)))->Expect.toBe(true)
    t->expect(shown(container))->Expect.toEqual([false, false, true])
    keyDown(all->Array.getUnsafe(2), "ArrowRight")->ignore
    t->expect(selected(container))->Expect.toEqual([Some("true"), Some("false"), Some("false")])
    click(all->Array.getUnsafe(2))
    t->expect(shown(container))->Expect.toEqual([false, false, true])
  })

  test("with manual activation, the arrows only move; Enter (a click) selects", t => {
    let container = tabs(~activation=#manual, ())
    let all = findAll(container, "[role=tab]")
    focus(all->Array.getUnsafe(0))
    keyDown(all->Array.getUnsafe(0), "End")->ignore
    t->expect(focused(all->Array.getUnsafe(2)))->Expect.toBe(true)
    t->expect(shown(container))->Expect.toEqual([true, false, false])
  })

  test("controlled, it reports a choice and shows its value", t => {
    let chosen = []
    let container = tabs(~value="a", ~onValueChange=value => chosen->Array.push(value), ())
    click(findAll(container, "[role=tab]")->Array.getUnsafe(2))
    t->expect(chosen)->Expect.toEqual(["c"])
    t->expect(shown(container))->Expect.toEqual([true, false, false])
  })

  test("TabsEntry makes a tab for each label, a panel for each element", t => {
    let container = mount(
      <TabsEntry labels=["One", "Two"] panels=[text("first"), text("second")] dataId="t" />,
    )
    t->expect(Dom.textContent(find(container, "[data-id=t-tab-1]")))->Expect.toBe("Two")
    click(find(container, "[data-id=t-tab-1]"))
    t->expect(attribute(find(container, "[data-id=t-panel-1]"), "hidden"))->Expect.toEqual(None)
  })
})

describe("Accordion and Collapsible", () => {
  let accordion =
    <Accordion.Root>
      <Accordion.Item name="faq" defaultOpen=true dataId="one">
        <Accordion.Trigger> {text("True to size?")} </Accordion.Trigger>
        <Accordion.Panel> {text("Yes.")} </Accordion.Panel>
      </Accordion.Item>
      <Accordion.Item name="faq" dataId="two">
        <Accordion.Trigger> {text("Returns?")} </Accordion.Trigger>
        <Accordion.Panel> {text("Within 30 days.")} </Accordion.Panel>
      </Accordion.Item>
    </Accordion.Root>

  test("is details and summary, sharing a name, the first open", t => {
    let container = mount(accordion)
    let items = findAll(container, "details")
    t
    ->expect(items->Array.map(item => attribute(item, "name")))
    ->Expect.toEqual([Some("faq"), Some("faq")])
    t->expect(items->Array.map(item => attribute(item, "open")))->Expect.toEqual([Some(""), None])
    t->expect(findAll(container, "details > summary")->Array.length)->Expect.toBe(2)
  })

  testAsync("renders on the server, with no hooks", async t => {
    let (payload, errors) = await serverRender(
      <div>
        accordion
        <Collapsible.Root>
          <Collapsible.Trigger> {text("More")} </Collapsible.Trigger>
          <Collapsible.Panel> {text("Hidden until opened")} </Collapsible.Panel>
        </Collapsible.Root>
      </div>,
    )
    t->expect(errors->Array.length)->Expect.toBe(0)
    t->expect(payload->String.includes(Collapsible.Styles.trigger))->Expect.toBe(true)
  })
})

describe("Combobox", () => {
  let fruit = ["Apple", "Apricot", "Banana", "Blueberry"]

  module Search = {
    @weft.component
    let make = (~onSelect: string => unit) => {
      let (text, setText) = Weft.Hooks.useState(() => "")
      let found =
        fruit->Array.filter(name =>
          text != "" && name->String.toLowerCase->String.startsWith(String.toLowerCase(text))
        )
      <form onSubmit={event => WeftDom.Dom.Event.preventDefault(event)}>
        <Field label="Fruit">
          <Combobox.Root onSelect>
            <Combobox.Input
              value=text
              dataId="input"
              onInput={event => setText(_ => WeftDom.Dom.Event.targetValue(event))}
            />
            {found == []
              ? Jsx.null
              : <Combobox.Popup>
                  {found
                  ->Array.map(name =>
                    <Combobox.Item key=name value=name disabled={name == "Apricot"}>
                      {Jsx.string(name)}
                    </Combobox.Item>
                  )
                  ->Jsx.array}
                </Combobox.Popup>}
          </Combobox.Root>
        </Field>
      </form>
    }
  }

  let search = () => {
    let chosen = []
    let container = mount(<Search onSelect={value => chosen->Array.push(value)} />)
    (container, chosen)
  }

  test(
    "is a combobox its field labels, controlling a listbox, expanded while it has suggestions",
    t => {
      let (container, _) = search()
      let input = find(container, "[data-id=input]")
      t->expect(attribute(input, "role"))->Expect.toEqual(Some("combobox"))
      t->expect(attribute(input, "aria-autocomplete"))->Expect.toEqual(Some("list"))
      t->expect(attribute(input, "aria-expanded"))->Expect.toEqual(Some("false"))
      t->expect(attribute(find(container, "label"), "for"))->Expect.toEqual(attribute(input, "id"))
      typeInto(input, "a")
      let listbox = find(container, "[role=listbox]")
      t->expect(attribute(input, "aria-controls"))->Expect.toEqual(attribute(listbox, "id"))
      t->expect(attribute(input, "aria-expanded"))->Expect.toEqual(Some("true"))
      t->expect(attribute(listbox, "data-popover-open"))->Expect.toEqual(Some(""))
      typeInto(input, "z")
      t->expect(attribute(input, "aria-expanded"))->Expect.toEqual(Some("false"))
    },
  )

  test(
    "the arrows highlight suggestions, past disabled ones, the focus staying in the input",
    t => {
      let (container, _) = search()
      let input = find(container, "[data-id=input]")
      focus(input)
      typeInto(input, "a")
      keyDown(input, "ArrowDown")->ignore
      let options = findAll(container, "[role=option]")
      let active = () =>
        attribute(input, "aria-activedescendant")->Option.flatMap(
          id =>
            Dom.querySelector(container, `#${id}`)->Nullable.toOption->Option.map(Dom.textContent),
        )
      t->expect(active())->Expect.toEqual(Some("Apple"))
      t
      ->expect(attribute(options->Array.getUnsafe(0), "aria-selected"))
      ->Expect.toEqual(Some("true"))
      keyDown(input, "ArrowDown")->ignore
      t->expect(active())->Expect.toEqual(Some("Apple"))
      keyDown(input, "ArrowUp")->ignore
      t->expect(active())->Expect.toEqual(Some("Apple"))
      t->expect(focused(input))->Expect.toBe(true)
    },
  )

  test("Enter chooses the highlighted one, and closes; with none, it's left alone", t => {
    let (container, chosen) = search()
    let input = find(container, "[data-id=input]")
    focus(input)
    typeInto(input, "b")
    let unhandled = keyDown(input, "Enter")
    t->expect(WeftDom.Dom.Event.defaultPrevented(unhandled))->Expect.toBe(false)
    keyDown(input, "ArrowDown")->ignore
    keyDown(input, "ArrowDown")->ignore
    keyDown(input, "Enter")->ignore
    t->expect(chosen)->Expect.toEqual(["Blueberry"])
    t->expect(attribute(input, "aria-expanded"))->Expect.toEqual(Some("false"))
  })

  test("Escape and leaving close it; a click chooses", t => {
    let (container, chosen) = search()
    let input = find(container, "[data-id=input]")
    focus(input)
    typeInto(input, "b")
    keyDown(input, "Escape")->ignore
    t->expect(attribute(input, "aria-expanded"))->Expect.toEqual(Some("false"))
    keyDown(input, "ArrowDown")->ignore
    t->expect(attribute(input, "aria-expanded"))->Expect.toEqual(Some("true"))
    blur(input)
    t->expect(attribute(input, "aria-expanded"))->Expect.toEqual(Some("false"))
    typeInto(input, "ba")
    click(find(container, "[role=option]"))
    t->expect(chosen)->Expect.toEqual(["Banana"])
  })
})
