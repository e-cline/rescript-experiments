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

module Styles = {
  let steps = Css.class({
    display: Flex,
    gap: Px(16),
    padding: Zero,
    listStyle: None,
    color: Var(Theme.muted),
    selectors: [("[aria-current=\"step\"]", Css.style({color: Var(Theme.ink), fontWeight: 600}))],
  })
  let field = Css.class({
    display: Grid,
    gap: Px(2),
    marginBottom: Px(10),
    maxWidth: Px(360),
    selectors: [
      (
        "input",
        Css.style({padding: Pair(Px(6), Px(8)), border: Theme.hairline(), borderRadius: Px(6)}),
      ),
    ],
  })
}

module Field = {
  @weft.component
  let make = (~label: string, ~name: string, ~value: string, ~autoComplete: string, ~onEdit) => {
    let id = Weft.Hooks.useId()
    <div className={Styles.field}>
      <label htmlFor=id> {WeftDom.Jsx.string(label)} </label>
      <input
        id name value autoComplete onInput={event => onEdit(WeftDom.Dom.Event.targetValue(event))}
      />
    </div>
  }
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
  <div dataId="checkout">
    <ol dataId="checkout-steps" className=Styles.steps>
      {[(Address, "Address"), (Delivery, "Delivery"), (Review, "Review")]
      ->Array.map(((step, label)) =>
        <li key=label ariaCurrent={step == state.step ? "step" : "false"}>
          {WeftDom.Jsx.string(label)}
        </li>
      )
      ->WeftDom.Jsx.array}
    </ol>
    <form
      dataId="checkout-form"
      onSubmit={event => {
        WeftDom.Dom.Event.preventDefault(event)
        state.step == Review ? place() : dispatch(Next)
      }}
    >
      {switch state.step {
      | Address =>
        <fieldset dataId="address-step">
          <legend> {WeftDom.Jsx.string("Where to?")} </legend>
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
        </fieldset>
      | Delivery =>
        <fieldset dataId="delivery-step">
          <legend> {WeftDom.Jsx.string("How fast?")} </legend>
          {[(Standard, "Standard (3–5 days)"), (Express, "Express (next day)")]
          ->Array.map(((delivery, label)) => {
            let value = delivery == Standard ? "standard" : "express"
            <label key=value className={Theme.choice}>
              <input
                type_="radio"
                name="delivery"
                dataId={`delivery-${value}`}
                value
                checked={details.delivery == delivery}
                onChange={_ => dispatch(Choose(delivery))}
              />
              {WeftDom.Jsx.string(
                ` ${label}: ${deliveryCost(delivery) == 0
                    ? "free"
                    : Money.format(deliveryCost(delivery), currency)}`,
              )}
            </label>
          })
          ->WeftDom.Jsx.array}
          <label htmlFor="gift-note"> {WeftDom.Jsx.string("Gift note (optional)")} </label>
          <textarea
            id="gift-note"
            rows=2
            value={details.giftNote->Option.getOr("")}
            onInput={event => edit(GiftNote, WeftDom.Dom.Event.targetValue(event))}
          />
        </fieldset>
      | Review =>
        <div dataId="review-step">
          <p dataId="review-address">
            {WeftDom.Jsx.string(
              `${details.name}, ${details.street}, ${details.city} ${details.postcode}`,
            )}
          </p>
          <p dataId="review-items"> {WeftDom.Jsx.string(`${Int.toString(count)} items`)} </p>
          <p dataId="review-total">
            {WeftDom.Jsx.string(
              `Total: ${Money.format(total + deliveryCost(details.delivery), currency)}`,
            )}
          </p>
        </div>
      }}
      {switch state.error {
      | Some(message) => <p dataId="checkout-error" role="alert"> {WeftDom.Jsx.string(message)} </p>
      | None => WeftDom.Jsx.null
      }}
      <div>
        {state.step == Address
          ? WeftDom.Jsx.null
          : <button dataId="checkout-back" type_="button" onClick={_ => dispatch(Back)}>
              {WeftDom.Jsx.string("Back")}
            </button>}
        <button dataId="checkout-next" type_="submit" disabled=state.placing>
          {WeftDom.Jsx.string(
            switch state.step {
            | Review => state.placing ? "Placing…" : "Place order"
            | _ => "Continue"
            },
          )}
        </button>
      </div>
    </form>
  </div>
}
