/***
Checking out, in three steps (a reducer): the address (checked as the `checkout.placeOrder` RPC will
check it, before moving on), delivery, then a review and placing the order. Its fields' labels are
linked by IDs from `useId`. If someone else bought the last of something meanwhile, the server says
which, and nothing is charged; otherwise it's on to the order's page.
*/

open Types

type step = Address | Delivery | Review

type state = {
  step: step,
  details: checkout,
  error: option<string>,
  placing: bool,
}

type field = Name | Street | City | Postcode | GiftNote

type action =
  | Edit(field, string)
  | Choose(delivery)
  | Next
  | Back
  | Placing
  | Failed(string)

let reducer = (state, action) =>
  switch action {
  | Edit(field, value) =>
    let details = state.details
    {
      ...state,
      details: switch field {
      | Name => {...details, name: value}
      | Street => {...details, street: value}
      | City => {...details, city: value}
      | Postcode => {...details, postcode: value}
      | GiftNote => {...details, giftNote: Some(value)}
      },
    }
  | Choose(delivery) => {...state, details: {...state.details, delivery}}
  | Next =>
    switch state.step {
    | Address =>
      switch Api.checkAddress(Api.trimmed(state.details)) {
      | Ok() => {...state, step: Delivery, error: None}
      | Error(error) => {...state, error: Some(Api.message(error))}
      }
    | Delivery => {...state, step: Review, error: None}
    | Review => state
    }
  | Back =>
    switch state.step {
    | Address | Delivery => {...state, step: Address, error: None}
    | Review => {...state, step: Delivery, error: None}
    }
  | Placing => {...state, placing: true, error: None}
  | Failed(error) => {...state, placing: false, error: Some(error)}
  }

open WeftCss
module Ui = WeftUi

module Styles = {
  let checkout = Css.class({maxWidth: Px(520)})
}

module Field = {
  @weft.component
  let make = (~label: string, ~name: string, ~value: string, ~autoComplete: string, ~onEdit) =>
    <Ui.Field label required=true>
      <Ui.Input
        name value autoComplete onInput={event => onEdit(WeftDom.Dom.Event.targetValue(event))}
      />
    </Ui.Field>
}

@weft.component({kind: Entrypoint})
let make = (~total: cents, ~count: int) => {
  let {currency, user} = ShopContext.use()
  let (state, dispatch) = Weft.Hooks.useReducer(
    reducer,
    {
      step: Address,
      details: {
        name: user->Option.getOr(""),
        street: "",
        city: "",
        postcode: "",
        delivery: Standard,
        giftNote: None,
      },
      error: None,
      placing: false,
    },
  )
  let navigation = WeftServer.Navigation.useNavigation()
  let placeOrder = WeftServer.Rpc.use(Api.placeOrder)
  let {details} = state
  let edit = (field, value) => dispatch(Edit(field, value))
  let place = () => {
    dispatch(Placing)

    (
      async () =>
        switch await placeOrder(details) {
        | Ok(orderId) => await navigation->WeftServer.Navigation.navigate(`/orders/${orderId}`)
        | Error(error) => dispatch(Failed(Api.describe(error)))
        }
    )()->ignore
  }
  let stepStatus = (step, ~rank) => {
    let current = switch state.step {
    | Address => 0
    | Delivery => 1
    | Review => 2
    }
    step == state.step ? #current : rank < current ? #complete : #upcoming
  }
  <Ui.Stack gap=#lg dataId="checkout" className=Styles.checkout>
    <Ui.Steps.Root ariaLabel="Checkout" dataId="checkout-steps">
      {[(Address, "Address", 0), (Delivery, "Delivery", 1), (Review, "Review", 2)]
      ->Array.map(((step, label, rank)) =>
        <Ui.Steps.Step key=label status={stepStatus(step, ~rank)}>
          {WeftDom.Jsx.string(label)}
        </Ui.Steps.Step>
      )
      ->WeftDom.Jsx.array}
    </Ui.Steps.Root>
    <Ui.Form
      dataId="checkout-form"
      busy=state.placing
      onSubmit={() => state.step == Review ? place() : dispatch(Next)}
    >
      {switch state.step {
      | Address =>
        <Ui.Fieldset legend="Where to?" dataId="address-step">
          <Field
            label="Name" name="name" value=details.name autoComplete="name" onEdit={edit(Name, ...)}
          />
          <Field
            label="Street"
            name="street"
            value=details.street
            autoComplete="address-line1"
            onEdit={edit(Street, ...)}
          />
          <Ui.Grid template="2fr 1fr" gap=#md stackBelow=#sm>
            <Field
              label="City"
              name="city"
              value=details.city
              autoComplete="address-level2"
              onEdit={edit(City, ...)}
            />
            <Field
              label="Postcode"
              name="postcode"
              value=details.postcode
              autoComplete="postal-code"
              onEdit={edit(Postcode, ...)}
            />
          </Ui.Grid>
        </Ui.Fieldset>
      | Delivery =>
        <Ui.Stack gap=#lg dataId="delivery-step">
          <Ui.RadioGroup.Root
            legend="How fast?"
            name="delivery"
            value={details.delivery == Standard ? "standard" : "express"}
            onValueChange={value => dispatch(Choose(value == "express" ? Express : Standard))}
          >
            {[(Standard, "Standard", "3–5 days"), (Express, "Express", "Next day")]
            ->Array.map(((delivery, label, days)) => {
              let value = delivery == Standard ? "standard" : "express"
              let cost =
                deliveryCost(delivery) == 0
                  ? "free"
                  : Money.format(deliveryCost(delivery), currency)
              <Ui.RadioGroup.Radio
                key=value value dataId={`delivery-${value}`} description={`${days}, ${cost}`}
              >
                {WeftDom.Jsx.string(label)}
              </Ui.RadioGroup.Radio>
            })
            ->WeftDom.Jsx.array}
          </Ui.RadioGroup.Root>
          <Ui.Field
            label="Gift note"
            description="Optional: we'll print it on the packing slip."
            id="gift-note"
          >
            <Ui.Textarea
              rows=2
              value={details.giftNote->Option.getOr("")}
              onInput={event => edit(GiftNote, WeftDom.Dom.Event.targetValue(event))}
            />
          </Ui.Field>
        </Ui.Stack>
      | Review =>
        <Ui.Card.Root dataId="review-step">
          <Ui.DescriptionList.Root>
            <Ui.DescriptionList.Term> {WeftDom.Jsx.string("To")} </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details dataId="review-address">
              {WeftDom.Jsx.string(
                `${details.name}, ${details.street}, ${details.city} ${details.postcode}`,
              )}
            </Ui.DescriptionList.Details>
            <Ui.DescriptionList.Term> {WeftDom.Jsx.string("Items")} </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details dataId="review-items">
              {WeftDom.Jsx.string(`${Int.toString(count)} items`)}
            </Ui.DescriptionList.Details>
            <Ui.DescriptionList.Term> {WeftDom.Jsx.string("Total")} </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details dataId="review-total">
              {WeftDom.Jsx.string(
                `Total: ${Money.format(total + deliveryCost(details.delivery), currency)}`,
              )}
            </Ui.DescriptionList.Details>
          </Ui.DescriptionList.Root>
        </Ui.Card.Root>
      }}
      {switch state.error {
      | Some(message) =>
        <Ui.Alert.Root tone=#danger dataId="checkout-error">
          <Ui.Alert.Description> {WeftDom.Jsx.string(message)} </Ui.Alert.Description>
        </Ui.Alert.Root>
      | None => WeftDom.Jsx.null
      }}
      <Ui.Stack direction=#row gap=#sm>
        {state.step == Address
          ? WeftDom.Jsx.null
          : <Ui.Button dataId="checkout-back" onClick={_ => dispatch(Back)}>
              {WeftDom.Jsx.string("Back")}
            </Ui.Button>}
        <Ui.Button dataId="checkout-next" type_=#submit variant=#primary busy=state.placing>
          {WeftDom.Jsx.string(
            switch state.step {
            | Review => state.placing ? "Placing…" : "Place order"
            | _ => "Continue"
            },
          )}
        </Ui.Button>
      </Ui.Stack>
    </Ui.Form>
  </Ui.Stack>
}
