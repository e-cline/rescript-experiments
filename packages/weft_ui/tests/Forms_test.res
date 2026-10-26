/*** The form controls: how a field labels and describes its control, and how each control behaves. */
open Vitest
open Support

describe("Field", () => {
  test("labels its control, and describes it with its description", t => {
    let container = mount(
      <Field label="Email" description="For the receipt">
        <Input type_=#email />
      </Field>,
    )
    let input = find(container, "input")
    let label = find(container, "label")
    t->expect(attribute(label, "for"))->Expect.toEqual(attribute(input, "id"))
    t->expect(Dom.textContent(label))->Expect.toBe("Email")
    let describedBy = attribute(input, "aria-describedby")->Option.getOr("")
    t->expect(Dom.textContent(find(container, `#${describedBy}`)))->Expect.toBe("For the receipt")
    t->expect(attribute(input, "aria-invalid"))->Expect.toEqual(None)
  })

  test("an error makes its control invalid, and describes it too, in a polite live region", t => {
    let container = mount(
      <Field label="Email" description="For the receipt" error="That's not an address">
        <Input />
      </Field>,
    )
    let input = find(container, "input")
    t->expect(attribute(input, "aria-invalid"))->Expect.toEqual(Some("true"))
    let ids = attribute(input, "aria-describedby")->Option.getOr("")->String.split(" ")
    t->expect(ids->Array.length)->Expect.toBe(2)
    let error = find(container, `#${ids->Array.getUnsafe(1)}`)
    t->expect(Dom.textContent(error))->Expect.toBe("That's not an address")
    t->expect(attribute(error, "aria-live"))->Expect.toEqual(Some("polite"))
  })

  test("its error region is there, empty, before there's an error", t => {
    let container = mount(
      <Field label="Name">
        <Input />
      </Field>,
    )
    t->expect(findAll(container, "[aria-live=polite]")->Array.length)->Expect.toBe(1)
    t->expect(attribute(find(container, "input"), "aria-describedby"))->Expect.toEqual(None)
  })

  test("required marks the label (not for assistive technology) and the control", t => {
    let container = mount(
      <Field label="Name" required=true>
        <Input />
      </Field>,
    )
    let input = find(container, "input")
    t->expect(attribute(input, "required"))->Expect.toEqual(Some(""))
    t->expect(attribute(input, "aria-required"))->Expect.toEqual(Some("true"))
    t->expect(attribute(find(container, "label span"), "aria-hidden"))->Expect.toEqual(Some("true"))
  })

  test("hideLabel keeps the label for assistive technology only", t => {
    let container = mount(
      <Field label="Search" hideLabel=true>
        <Input type_=#search />
      </Field>,
    )
    t->expect(has(find(container, "label"), VisuallyHidden.className))->Expect.toBe(true)
  })

  test("labels a textarea, a select and a number field the same way", t => {
    let check = control => {
      let container = mount(<Field label="It"> control </Field>)
      let id = attribute(find(container, "label"), "for")
      t->expect(id->Option.isSome)->Expect.toBe(true)
      t->expect(findAll(container, `#${id->Option.getOr("")}`)->Array.length)->Expect.toBe(1)
    }
    check(<Textarea />)
    check(
      <Select>
        <Select.Option value="a"> {text("A")} </Select.Option>
      </Select>,
    )
    check(
      <NumberField.Root>
        <NumberField.Input />
      </NumberField.Root>,
    )
  })

  test("a control outside a field keeps its own label and id", t => {
    let input = find(mount(<Input id="mine" ariaLabel="Filter" />), "input")
    t->expect(attribute(input, "id"))->Expect.toEqual(Some("mine"))
    t->expect(attribute(input, "aria-label"))->Expect.toEqual(Some("Filter"))
  })
})

describe("Select", () => {
  test("is controlled by value, and reports a choice", t => {
    let chosen = ref("")
    let container = mount(
      <Select value="b" onChange={event => chosen := WeftDom.Dom.Event.targetValue(event)}>
        <Select.Option value="a"> {text("A")} </Select.Option>
        <Select.Option value="b"> {text("B")} </Select.Option>
      </Select>,
    )
    let select = find(container, "select")
    t->expect(toString(property(select, "value")))->Expect.toBe("b")
    WeftDom.Client.act(
      () => {
        Dom.setProperty(select, "value", Obj.magic("a"))
        Dom.dispatchEvent(select, Dom.Event.make("change", {bubbles: true}))
      },
    )
    t->expect(chosen.contents)->Expect.toBe("a")
  })
})

describe("Checkbox and Switch", () => {
  test("a checkbox reports its new state, labelled by its text", t => {
    let states = []
    let container = mount(
      <Checkbox onCheckedChange={checked => states->Array.push(checked)} description="Only those">
        {text("On sale")}
      </Checkbox>,
    )
    let input = find(container, "input")
    click(input)
    click(input)
    t->expect(states)->Expect.toEqual([true, false])
    t->expect(Dom.textContent(find(container, "label")))->Expect.toBe("On saleOnly those")
    let describedBy = attribute(input, "aria-describedby")->Option.getOr("")
    t->expect(Dom.textContent(find(container, `#${describedBy}`)))->Expect.toBe("Only those")
  })

  test("a controlled checkbox shows its prop", t => {
    let input = find(mount(<Checkbox checked=true onCheckedChange={_ => ()} />), "input")
    click(input)
    t->expect(toBool(property(input, "checked")))->Expect.toBe(true)
  })

  test("indeterminate is the property, and aria-checked mixed", t => {
    let input = find(mount(<Checkbox indeterminate=true />), "input")
    t->expect(toBool(property(input, "indeterminate")))->Expect.toBe(true)
    t->expect(attribute(input, "aria-checked"))->Expect.toEqual(Some("mixed"))
  })

  test("a switch is a checkbox with the switch role", t => {
    let states = []
    let input = find(
      mount(
        <Switch onCheckedChange={checked => states->Array.push(checked)}> {text("Wi-Fi")} </Switch>,
      ),
      "input",
    )
    t->expect(attribute(input, "role"))->Expect.toEqual(Some("switch"))
    click(input)
    t->expect(states)->Expect.toEqual([true])
  })
})

describe("RadioGroup and Fieldset", () => {
  test("its radios share a name, in a fieldset its legend names", t => {
    let container = mount(
      <RadioGroup.Root legend="Delivery" defaultValue="standard">
        <RadioGroup.Radio value="standard"> {text("Standard")} </RadioGroup.Radio>
        <RadioGroup.Radio value="express"> {text("Express")} </RadioGroup.Radio>
      </RadioGroup.Root>,
    )
    t->expect(Dom.textContent(find(container, "fieldset > legend")))->Expect.toBe("Delivery")
    let radios = findAll(container, "input[type=radio]")
    let names = radios->Array.map(radio => attribute(radio, "name"))
    t->expect(names->Array.getUnsafe(0)->Option.isSome)->Expect.toBe(true)
    t->expect(names->Array.getUnsafe(0))->Expect.toEqual(names->Array.getUnsafe(1))
    t
    ->expect(radios->Array.map(radio => toBool(property(radio, "checked"))))
    ->Expect.toEqual([true, false])
    click(radios->Array.getUnsafe(1))
    t
    ->expect(radios->Array.map(radio => toBool(property(radio, "checked"))))
    ->Expect.toEqual([false, true])
  })

  test("a controlled group reports a choice and shows its value", t => {
    let chosen = []
    let container = mount(
      <RadioGroup.Root legend="Size" value="m" onValueChange={value => chosen->Array.push(value)}>
        <RadioGroup.Radio value="s"> {text("S")} </RadioGroup.Radio>
        <RadioGroup.Radio value="m"> {text("M")} </RadioGroup.Radio>
      </RadioGroup.Root>,
    )
    let radios = findAll(container, "input")
    click(radios->Array.getUnsafe(0))
    t->expect(chosen)->Expect.toEqual(["s"])
    t
    ->expect(radios->Array.map(radio => toBool(property(radio, "checked"))))
    ->Expect.toEqual([false, true])
  })

  test("a fieldset's error describes it, and disabled disables what's in it", t => {
    let container = mount(
      <Fieldset legend="Address" error="Fill in every line" disabled=true>
        <Input />
      </Fieldset>,
    )
    let fieldset = find(container, "fieldset")
    let describedBy = attribute(fieldset, "aria-describedby")->Option.getOr("")
    t
    ->expect(Dom.textContent(find(container, `#${describedBy}`)))
    ->Expect.toBe("Fill in every line")
    t->expect(Dom.matches(find(container, "input"), ":disabled"))->Expect.toBe(true)
  })
})

describe("NumberField", () => {
  let field = (~onValueChange=?, ~defaultValue=2., ()) =>
    mount(
      <NumberField.Root ?onValueChange defaultValue min=1. max=5.>
        <NumberField.Decrement />
        <NumberField.Input />
        <NumberField.Increment />
      </NumberField.Root>,
    )

  test("is a spinbutton with its value and bounds", t => {
    let input = find(field(), "input")
    t->expect(attribute(input, "role"))->Expect.toEqual(Some("spinbutton"))
    t
    ->expect(["aria-valuenow", "aria-valuemin", "aria-valuemax"]->Array.map(attribute(input, ...)))
    ->Expect.toEqual([Some("2"), Some("1"), Some("5")])
  })

  test("steps with the arrow keys, within its bounds, and Home and End go to them", t => {
    let values = []
    let input = find(field(~onValueChange=value => values->Array.push(value), ()), "input")
    keyDown(input, "ArrowUp")->ignore
    keyDown(input, "ArrowDown")->ignore
    keyDown(input, "ArrowDown")->ignore
    keyDown(input, "ArrowDown")->ignore
    keyDown(input, "End")->ignore
    keyDown(input, "PageUp")->ignore
    keyDown(input, "Home")->ignore
    t->expect(values)->Expect.toEqual([3., 2., 1., 5., 1.])
    t->expect(toString(property(input, "value")))->Expect.toBe("1")
  })

  test("commits what's typed on blur, kept in bounds, and puts back what isn't a number", t => {
    let input = find(field(), "input")
    typeInto(input, "4")
    t->expect(attribute(input, "aria-valuenow"))->Expect.toEqual(Some("2"))
    blur(input)
    t->expect(attribute(input, "aria-valuenow"))->Expect.toEqual(Some("4"))
    typeInto(input, "40")
    blur(input)
    t->expect(toString(property(input, "value")))->Expect.toBe("5")
    typeInto(input, "lots")
    blur(input)
    t->expect(toString(property(input, "value")))->Expect.toBe("5")
  })

  test("its buttons step, are named, out of the tab order, and disabled at the ends", t => {
    let container = field(~defaultValue=4., ())
    let buttons = findAll(container, "button")
    let increase = buttons->Array.getUnsafe(1)
    t
    ->expect(buttons->Array.map(button => attribute(button, "aria-label")))
    ->Expect.toEqual([Some("Decrease"), Some("Increase")])
    t->expect(attribute(increase, "tabindex"))->Expect.toEqual(Some("-1"))
    click(increase)
    t->expect(attribute(find(container, "input"), "aria-valuenow"))->Expect.toEqual(Some("5"))
    t->expect(Dom.matches(increase, ":disabled"))->Expect.toBe(true)
  })
})

describe("Form", () => {
  test("calls onSubmit instead of submitting, unless it's busy", t => {
    let submits = ref(0)
    let form = busy =>
      <Form busy onSubmit={() => submits := submits.contents + 1}>
        <Button type_=#submit> {text("Save")} </Button>
      </Form>
    click(find(mount(form(false)), "button"))
    t->expect(submits.contents)->Expect.toBe(1)
    let busy = mount(form(true))
    click(find(busy, "button"))
    t->expect(submits.contents)->Expect.toBe(1)
    t->expect(attribute(find(busy, "form"), "aria-busy"))->Expect.toEqual(Some("true"))
    t->expect(attribute(find(busy, "form"), "novalidate"))->Expect.toEqual(Some(""))
  })

  test("shows its error as an alert at its top", t => {
    let container = mount(
      <Form error="The server said no">
        <Input />
      </Form>,
    )
    let alert = find(container, "form > [role=alert]")
    t->expect(Dom.textContent(alert))->Expect.toBe("The server said no")
  })
})

describe("Toggle and ToggleGroup", () => {
  test("a toggle is pressed and unpressed, its label the same", t => {
    let states = []
    let button = find(
      mount(
        <Toggle label="Save to wishlist" onPressedChange={pressed => states->Array.push(pressed)}>
          {text("♥")}
        </Toggle>,
      ),
      "button",
    )
    click(button)
    t->expect(attribute(button, "aria-pressed"))->Expect.toEqual(Some("true"))
    click(button)
    t->expect(attribute(button, "aria-pressed"))->Expect.toEqual(Some("false"))
    t->expect(states)->Expect.toEqual([true, false])
    t->expect(attribute(button, "aria-label"))->Expect.toEqual(Some("Save to wishlist"))
    t->expect(attribute(find(button, "span"), "aria-hidden"))->Expect.toEqual(Some("true"))
  })

  let sizes = (~type_=?, ~defaultValue=?, ()) =>
    mount(
      <ToggleGroup.Root label="Size" ?type_ ?defaultValue>
        <ToggleGroup.Item value="s"> {text("S")} </ToggleGroup.Item>
        <ToggleGroup.Item value="m"> {text("M")} </ToggleGroup.Item>
        <ToggleGroup.Item value="l" disabled=true> {text("L")} </ToggleGroup.Item>
        <ToggleGroup.Item value="xl"> {text("XL")} </ToggleGroup.Item>
      </ToggleGroup.Root>,
    )
  let pressed = container =>
    findAll(container, "button")->Array.map(button => attribute(button, "aria-pressed"))

  test("a single group has one pressed, which stays pressed when pressed again", t => {
    let container = sizes(~defaultValue=["s"], ())
    let group = find(container, "[role=group]")
    t->expect(attribute(group, "aria-label"))->Expect.toEqual(Some("Size"))
    click(findAll(container, "button")->Array.getUnsafe(1))
    click(findAll(container, "button")->Array.getUnsafe(1))
    t
    ->expect(pressed(container))
    ->Expect.toEqual([Some("false"), Some("true"), Some("false"), Some("false")])
  })

  test("a multiple group presses and unpresses each", t => {
    let container = sizes(~type_=#multiple, ())
    let buttons = findAll(container, "button")
    click(buttons->Array.getUnsafe(0))
    click(buttons->Array.getUnsafe(3))
    click(buttons->Array.getUnsafe(0))
    t
    ->expect(pressed(container))
    ->Expect.toEqual([Some("false"), Some("false"), Some("false"), Some("true")])
  })

  test("is one Tab stop, the pressed item, and the arrow keys move past disabled ones", t => {
    let container = sizes(~defaultValue=["m"], ())
    let buttons = findAll(container, "button")
    t
    ->expect(buttons->Array.map(button => attribute(button, "tabindex")))
    ->Expect.toEqual([Some("-1"), Some("0"), Some("-1"), Some("-1")])
    let m = buttons->Array.getUnsafe(1)
    focus(m)
    let event = keyDown(m, "ArrowRight")
    t->expect(activeElement() == Some(buttons->Array.getUnsafe(3)))->Expect.toBe(true)
    t->expect(WeftDom.Dom.Event.defaultPrevented(event))->Expect.toBe(true)
    keyDown(buttons->Array.getUnsafe(3), "ArrowRight")->ignore
    t->expect(activeElement() == Some(buttons->Array.getUnsafe(0)))->Expect.toBe(true)
    keyDown(buttons->Array.getUnsafe(0), "End")->ignore
    t->expect(activeElement() == Some(buttons->Array.getUnsafe(3)))->Expect.toBe(true)
    // The item focused last is the Tab stop now.
    t->expect(attribute(buttons->Array.getUnsafe(3), "tabindex"))->Expect.toEqual(Some("0"))
  })
})
