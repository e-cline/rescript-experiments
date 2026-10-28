/***
The forms page's examples: entrypoints, since form controls keep state (or read their field's).
*/

module Ui = WeftUi
module Event = WeftDom.Dom.Event
module Jsx = WeftDom.Jsx

let text = Jsx.string

module SignUp = {
  /** A form that checks itself on submit, shows each field's error, then is busy, then done. */
  type errors = {name: option<string>, email: option<string>, terms: option<string>}

  let check = (~name, ~email, ~terms) => {
    name: String.trim(name) == "" ? Some("Enter your name.") : None,
    email: email->String.includes("@")
      ? None
      : Some("Enter an email address, like ada@example.com."),
    terms: terms ? None : Some("Agree to the terms to sign up."),
  }

  @weft.component({kind: Entrypoint})
  let make = () => {
    let (name, setName) = Weft.Hooks.useState(() => "")
    let (email, setEmail) = Weft.Hooks.useState(() => "")
    let (plan, setPlan) = Weft.Hooks.useState(() => "free")
    let (bio, setBio) = Weft.Hooks.useState(() => "")
    let (terms, setTerms) = Weft.Hooks.useState(() => false)
    let (errors, setErrors) = Weft.Hooks.useState(() => None)
    let (status, setStatus) = Weft.Hooks.useState(() => #editing)
    Weft.Hooks.useEffect1(() =>
      switch status {
      | #saving =>
        let timer = setTimeout(() => setStatus(_ => #done), 800)
        Some(() => clearTimeout(timer))
      | #editing | #done => None
      }
    , [status])
    let submit = () => {
      let found = check(~name, ~email, ~terms)
      switch found {
      | {name: None, email: None, terms: None} =>
        setErrors(_ => None)
        setStatus(_ => #saving)
      | _ => setErrors(_ => Some(found))
      }
    }
    let error = field => errors->Option.flatMap(field)
    switch status {
    | #done =>
      <Ui.Alert.Root tone=#success dataId="signup-done">
        <Ui.Alert.Title> {text(`Welcome, ${name}`)} </Ui.Alert.Title>
        <Ui.Alert.Description> {text("You're signed up.")} </Ui.Alert.Description>
      </Ui.Alert.Root>
    | #editing | #saving =>
      <Ui.Form
        dataId="signup"
        onSubmit=submit
        busy={status == #saving}
        error=?{errors->Option.map(_ => "Some of these need another look.")}
      >
        <Ui.Grid columns=2 stackBelow=#sm gap=#lg>
          <Ui.Field label="Name" required=true error=?{error(errors => errors.name)}>
            <Ui.Input
              dataId="signup-name"
              value=name
              autoComplete="name"
              onInput={event => setName(_ => Event.targetValue(event))}
            />
          </Ui.Field>
          <Ui.Field
            label="Email"
            required=true
            description="We'll send a confirmation here."
            error=?{error(errors => errors.email)}
          >
            <Ui.Input
              dataId="signup-email"
              type_=#email
              value=email
              autoComplete="email"
              onInput={event => setEmail(_ => Event.targetValue(event))}
            />
          </Ui.Field>
        </Ui.Grid>
        <Ui.Field label="Plan">
          <Ui.Select value=plan onChange={event => setPlan(_ => Event.targetValue(event))}>
            <Ui.Select.Option value="free"> {text("Free")} </Ui.Select.Option>
            <Ui.Select.Option value="pro"> {text("Pro ($8 a month)")} </Ui.Select.Option>
            <Ui.Select.Option value="team"> {text("Team ($20 a month)")} </Ui.Select.Option>
          </Ui.Select>
        </Ui.Field>
        <Ui.Field label="About you" description="Optional: a line or two.">
          <Ui.Textarea value=bio onInput={event => setBio(_ => Event.targetValue(event))} />
        </Ui.Field>
        <Ui.Fieldset legend="Terms" hideLegend=true error=?{error(errors => errors.terms)}>
          <Ui.Checkbox
            dataId="signup-terms" checked=terms onCheckedChange={checked => setTerms(_ => checked)}
          >
            {text("I agree to the terms")}
          </Ui.Checkbox>
        </Ui.Fieldset>
        <Ui.Stack direction=#row>
          <Ui.Button dataId="signup-submit" type_=#submit variant=#primary busy={status == #saving}>
            {text(status == #saving ? "Signing up…" : "Sign up")}
          </Ui.Button>
        </Ui.Stack>
      </Ui.Form>
    }
  }
}

module States = {
  /** Inputs in each size, and disabled and invalid. */
  @weft.component({kind: Entrypoint})
  let make = () =>
    <Ui.Grid minItemWidth="200px" gap=#lg>
      <Ui.Field label="Small">
        <Ui.Input size=#sm placeholder="size=#sm" />
      </Ui.Field>
      <Ui.Field label="Medium">
        <Ui.Input placeholder="size=#md" />
      </Ui.Field>
      <Ui.Field label="Large">
        <Ui.Input size=#lg placeholder="size=#lg" />
      </Ui.Field>
      <Ui.Field label="Disabled" disabled=true>
        <Ui.Input value="Can't change this" />
      </Ui.Field>
      <Ui.Field label="Invalid" error="Too short">
        <Ui.Input value="ab" />
      </Ui.Field>
      <Ui.Field label="Search" hideLabel=true>
        <Ui.Input type_=#search placeholder="Search (label hidden)" />
      </Ui.Field>
    </Ui.Grid>
}

module Choices = {
  /** Checkboxes with a "select all" over them, radio buttons, and a switch. */
  let toppings = ["Cheese", "Mushrooms", "Olives"]

  @weft.component({kind: Entrypoint})
  let make = () => {
    let (chosen, setChosen) = Weft.Hooks.useState(() => ["Cheese"])
    let (delivery, setDelivery) = Weft.Hooks.useState(() => "standard")
    let (notify, setNotify) = Weft.Hooks.useState(() => true)
    let all = Array.length(chosen) == Array.length(toppings)
    <Ui.Grid minItemWidth="220px" gap=#xl>
      <Ui.Fieldset legend="Toppings" gap=#sm>
        <Ui.Checkbox
          checked=all
          indeterminate={!all && chosen != []}
          onCheckedChange={checked => setChosen(_ => checked ? toppings : [])}
        >
          {text("All of them")}
        </Ui.Checkbox>
        {toppings
        ->Array.map(topping =>
          <Ui.Checkbox
            key=topping
            checked={chosen->Array.includes(topping)}
            onCheckedChange={checked =>
              setChosen(chosen =>
                checked ? [...chosen, topping] : chosen->Array.filter(other => other != topping)
              )}
          >
            {text(topping)}
          </Ui.Checkbox>
        )
        ->Jsx.array}
      </Ui.Fieldset>
      <Ui.RadioGroup.Root
        legend="Delivery" value=delivery onValueChange={value => setDelivery(_ => value)}
      >
        <Ui.RadioGroup.Radio value="standard" description="3–5 days, free">
          {text("Standard")}
        </Ui.RadioGroup.Radio>
        <Ui.RadioGroup.Radio value="express" description="Next day, $9">
          {text("Express")}
        </Ui.RadioGroup.Radio>
        <Ui.RadioGroup.Radio value="pickup" disabled=true description="Not near you">
          {text("Pick up")}
        </Ui.RadioGroup.Radio>
      </Ui.RadioGroup.Root>
      <Ui.Fieldset legend="Settings" gap=#sm>
        <Ui.Switch checked=notify onCheckedChange={checked => setNotify(_ => checked)}>
          {text("Email me about my order")}
        </Ui.Switch>
        <Ui.Switch disabled=true> {text("Text me (disabled)")} </Ui.Switch>
      </Ui.Fieldset>
    </Ui.Grid>
  }
}

module Numbers = {
  /** Number fields: a quantity in bounds, and a price stepping by a half. */
  @weft.component({kind: Entrypoint})
  let make = () =>
    <Ui.Stack direction=#row gap=#xl wrap=true>
      <Ui.Field label="Quantity" description="From 1 to 10">
        <Ui.NumberField.Root defaultValue=1. min=1. max=10.>
          <Ui.NumberField.Decrement />
          <Ui.NumberField.Input dataId="quantity" />
          <Ui.NumberField.Increment />
        </Ui.NumberField.Root>
      </Ui.Field>
      <Ui.Field label="Price">
        <Ui.NumberField.Root defaultValue=9.5 min=0. step=0.5 size=#sm>
          <Ui.NumberField.Decrement />
          <Ui.NumberField.Input />
          <Ui.NumberField.Increment />
        </Ui.NumberField.Root>
      </Ui.Field>
    </Ui.Stack>
}

module Toggles = {
  /** Toggles: text ones, an icon one, and groups of them. */
  @weft.component({kind: Entrypoint})
  let make = () => {
    let (saved, setSaved) = Weft.Hooks.useState(() => false)
    <Ui.Stack gap=#lg>
      <Ui.Stack direction=#row gap=#sm align=#center>
        <Ui.Toggle defaultPressed=true> {text("Bold")} </Ui.Toggle>
        <Ui.Toggle> {text("Italic")} </Ui.Toggle>
        <Ui.Toggle
          label="Save to wishlist"
          variant=#ghost
          pressed=saved
          onPressedChange={pressed => setSaved(_ => pressed)}
        >
          {text(saved ? "♥" : "♡")}
        </Ui.Toggle>
      </Ui.Stack>
      <Ui.ToggleGroup.Root label="Size" defaultValue=["m"] dataId="sizes">
        {["XS", "S", "M", "L", "XL"]
        ->Array.map(size =>
          <Ui.ToggleGroup.Item key=size value={String.toLowerCase(size)} disabled={size == "XS"}>
            {text(size)}
          </Ui.ToggleGroup.Item>
        )
        ->Jsx.array}
      </Ui.ToggleGroup.Root>
      <Ui.ToggleGroup.Root label="Extras" type_=#multiple variant=#ghost size=#sm>
        {["Gift wrap", "Card", "Ribbon"]
        ->Array.map(extra =>
          <Ui.ToggleGroup.Item key=extra value=extra> {text(extra)} </Ui.ToggleGroup.Item>
        )
        ->Jsx.array}
      </Ui.ToggleGroup.Root>
    </Ui.Stack>
  }
}
