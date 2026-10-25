/*** The static components in the page: their elements, ARIA and classes. */
open Vitest
open Support

describe("conventions", () => {
  test("className goes last, after the component's own classes", t => {
    let container = mount(<Badge tone=#accent className="mine"> {text("New")} </Badge>)
    let badge = find(container, "span")
    t->expect(classes(badge)->Array.at(-1))->Expect.toEqual(Some("mine"))
    t->expect(has(badge, Badge.Styles.softAccent))->Expect.toBe(true)
  })

  test("a recipe is the component's own classes", t => {
    let container = mount(<Button variant=#primary size=#sm> {text("Go")} </Button>)
    t
    ->expect(attribute(find(container, "button"), "class"))
    ->Expect.toEqual(Some(Button.className(~variant=#primary, ~size=#sm, ())))
  })

  test("attrs adds what a part doesn't take; its own props win", t => {
    let container = mount(
      <Button dataId="mine" attrs={{title: "from attrs", dataId: "theirs", ariaHidden: "false"}}>
        {text("Go")}
      </Button>,
    )
    let button = find(container, "button")
    t->expect(attribute(button, "data-id"))->Expect.toEqual(Some("mine"))
    t->expect(attribute(button, "aria-hidden"))->Expect.toEqual(Some("false"))
    // `title` is one of Button's own props: absent, it wipes `attrs.title` (see the plan, §4).
    t->expect(attribute(button, "title"))->Expect.toEqual(None)
  })
})

describe("layout", () => {
  test("Stack picks its element and classes", t => {
    let container = mount(
      <Stack as_=#ul direction=#row gap=#xs align=#center justify=#between wrap=true />,
    )
    let list = find(container, "ul")
    [
      Stack.Styles.row,
      Stack.Styles.gapXs,
      Stack.Styles.alignCenter,
      Stack.Styles.justifyBetween,
      Stack.Styles.wrap,
    ]->Array.forEach(className => t->expect(has(list, className))->Expect.toBe(true))
  })

  test("Grid sets its columns as a variable: a template, a minimum width, or a count", t => {
    let style = element => attribute(element, "style")->Option.getOr("")
    let byTemplate = find(mount(<Grid template="220px 1fr" />), "div")
    t->expect(has(byTemplate, Grid.Styles.byTemplate))->Expect.toBe(true)
    t->expect(style(byTemplate)->String.includes("220px 1fr"))->Expect.toBe(true)
    let byWidth = find(mount(<Grid minItemWidth="180px" style={dict{"color": "red"}} />), "div")
    t->expect(has(byWidth, Grid.Styles.byWidth))->Expect.toBe(true)
    t->expect(style(byWidth)->String.includes("180px"))->Expect.toBe(true)
    t->expect(style(byWidth)->String.includes("red"))->Expect.toBe(true)
    t->expect(has(find(mount(<Grid columns=3 />), "div"), Grid.Styles.byCount))->Expect.toBe(true)
  })

  test("Separator is a separator, or nothing to assistive technology when decorative", t => {
    let vertical = find(mount(<Separator orientation=#vertical />), "div")
    t->expect(attribute(vertical, "role"))->Expect.toEqual(Some("separator"))
    t->expect(attribute(vertical, "aria-orientation"))->Expect.toEqual(Some("vertical"))
    let decorative = find(mount(<Separator decorative=true />), "div")
    t->expect(attribute(decorative, "role"))->Expect.toEqual(Some("none"))
  })
})

describe("text", () => {
  test("Heading is its level's element, at its level's size unless told", t => {
    let h3 = find(mount(<Heading level=#h3> {text("T")} </Heading>), "h3")
    t->expect(has(h3, Heading.Styles.lg))->Expect.toBe(true)
    let small = find(mount(<Heading level=#h1 size=#sm> {text("T")} </Heading>), "h1")
    t->expect(has(small, Heading.Styles.sm))->Expect.toBe(true)
  })

  test("an external link opens a new tab, and says so", t => {
    let link = find(
      mount(<Link href="https://example.com" external_=true> {text("Docs")} </Link>),
      "a",
    )
    t->expect(attribute(link, "target"))->Expect.toEqual(Some("_blank"))
    t->expect(attribute(link, "rel"))->Expect.toEqual(Some("noopener noreferrer"))
    t->expect(Dom.textContent(link))->Expect.toBe("Docs (opens in a new tab)")
  })
})

describe("surfaces", () => {
  test("Alert's role follows its tone, unless it's given one", t => {
    let role = element => attribute(find(mount(element), "div"), "role")
    t->expect(role(<Alert.Root tone=#danger />))->Expect.toEqual(Some("alert"))
    t->expect(role(<Alert.Root tone=#warning />))->Expect.toEqual(Some("alert"))
    t->expect(role(<Alert.Root tone=#success />))->Expect.toEqual(Some("status"))
    t->expect(role(<Alert.Root tone=#danger role=#none />))->Expect.toEqual(None)
    t->expect(role(<Alert.Root tone=#info role=#alert />))->Expect.toEqual(Some("alert"))
  })

  test("Card.Title is an h3 unless its level says otherwise", t => {
    let container = mount(
      <Card.Root>
        <Card.Title> {text("A")} </Card.Title>
        <Card.Title level=#h2> {text("B")} </Card.Title>
      </Card.Root>,
    )
    t->expect(Dom.textContent(find(container, "h3")))->Expect.toBe("A")
    t->expect(Dom.textContent(find(container, "h2")))->Expect.toBe("B")
  })
})

describe("data", () => {
  test("a list without markers keeps its list role", t => {
    t->expect(attribute(find(mount(<List.Root />), "ul"), "role"))->Expect.toEqual(Some("list"))
    t
    ->expect(attribute(find(mount(<List.Root markers=true />), "ul"), "role"))
    ->Expect.toEqual(None)
  })

  test("a table's scrolling box is a focusable region when it has a label", t => {
    let container = mount(
      <Table.Root scrollLabel="Orders">
        <Table.Body>
          <Table.Row selected=true>
            <Table.HeaderCell scope=#row> {text("A1")} </Table.HeaderCell>
            <Table.Cell numeric=true> {text("4")} </Table.Cell>
          </Table.Row>
        </Table.Body>
      </Table.Root>,
    )
    let region = find(container, "div")
    t->expect(attribute(region, "role"))->Expect.toEqual(Some("region"))
    t->expect(attribute(region, "aria-label"))->Expect.toEqual(Some("Orders"))
    t->expect(attribute(region, "tabindex"))->Expect.toEqual(Some("0"))
    t->expect(attribute(find(container, "th"), "scope"))->Expect.toEqual(Some("row"))
    t->expect(has(find(container, "td"), Table.Styles.numeric))->Expect.toBe(true)
    t->expect(attribute(find(container, "tr"), "data-state"))->Expect.toEqual(Some("selected"))
    let plain = find(mount(<Table.Root />), "div")
    t
    ->expect((attribute(plain, "role"), attribute(plain, "tabindex")))
    ->Expect.toEqual((None, None))
  })

  test("breadcrumbs are a named nav, the page itself current", t => {
    let container = mount(
      <Breadcrumbs.Root>
        <Breadcrumbs.Item>
          <a href="/"> {text("Home")} </a>
        </Breadcrumbs.Item>
        <Breadcrumbs.Current> {text("Here")} </Breadcrumbs.Current>
      </Breadcrumbs.Root>,
    )
    t->expect(attribute(find(container, "nav"), "aria-label"))->Expect.toEqual(Some("Breadcrumbs"))
    t->expect(Dom.textContent(find(container, "[aria-current=page]")))->Expect.toBe("Here")
    t->expect(findAll(container, "ol > li")->Array.length)->Expect.toBe(2)
  })

  test("steps mark the current one, and say which are done", t => {
    let container = mount(
      <Steps.Root ariaLabel="Checkout">
        <Steps.Step status=#complete> {text("Address")} </Steps.Step>
        <Steps.Step status=#current> {text("Delivery")} </Steps.Step>
        <Steps.Step status=#upcoming> {text("Review")} </Steps.Step>
      </Steps.Root>,
    )
    let steps = findAll(container, "li")
    t
    ->expect(steps->Array.map(step => attribute(step, "aria-current")))
    ->Expect.toEqual([None, Some("step"), None])
    t
    ->expect(steps->Array.map(Dom.textContent))
    ->Expect.toEqual(["Address (done)", "Delivery", "Review"])
  })
})

describe("status", () => {
  test("a spinner is a status with its label, unless it isn't announced", t => {
    let announced = find(mount(<Spinner label="Saving" />), "[role=status]")
    t->expect(Dom.textContent(announced))->Expect.toBe("Saving")
    let quiet = mount(<Spinner announce=false />)
    t->expect(findAll(quiet, "[role=status]")->Array.length)->Expect.toBe(0)
  })

  test("a skeleton is hidden from assistive technology, a line each", t => {
    let container = mount(<Skeleton lines=3 />)
    t->expect(attribute(find(container, "span"), "aria-hidden"))->Expect.toEqual(Some("true"))
    t->expect(findAll(container, "span > span")->Array.length)->Expect.toBe(3)
  })
})

describe("buttons", () => {
  test("a button is type=button unless told, and calls onClick", t => {
    let clicks = ref(0)
    let button = find(mount(<Button onClick={_ => clicks := clicks.contents + 1} />), "button")
    t->expect(attribute(button, "type"))->Expect.toEqual(Some("button"))
    click(button)
    t->expect(clicks.contents)->Expect.toBe(1)
  })

  test("a busy button keeps its focus and stops clicks, with a spinner", t => {
    let clicks = ref(0)
    let button = find(
      mount(
        <Button busy=true onClick={_ => clicks := clicks.contents + 1}> {text("Save")} </Button>,
      ),
      "button",
    )
    click(button)
    t->expect(clicks.contents)->Expect.toBe(0)
    t->expect(attribute(button, "aria-disabled"))->Expect.toEqual(Some("true"))
    t->expect(attribute(button, "disabled"))->Expect.toEqual(None)
    t->expect(findAll(button, "[aria-hidden=true]")->Array.length)->Expect.toBe(1)
  })

  test("a busy submit button doesn't submit its form", t => {
    let submits = ref(0)
    let container = mount(
      <form
        onSubmit={event => {
          WeftDom.Dom.Event.preventDefault(event)
          submits := submits.contents + 1
        }}
      >
        <Button type_=#submit busy=true> {text("Save")} </Button>
      </form>,
    )
    click(find(container, "button"))
    t->expect(submits.contents)->Expect.toBe(0)
  })

  test("an icon button is named by its label, its icon hidden", t => {
    let button = find(mount(<IconButton label="Dismiss"> {text("×")} </IconButton>), "button")
    t->expect(attribute(button, "aria-label"))->Expect.toEqual(Some("Dismiss"))
    t->expect(attribute(find(button, "span"), "aria-hidden"))->Expect.toEqual(Some("true"))
  })
})
