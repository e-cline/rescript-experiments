/***
What a `Field` tells the control in it: its `id` (the label's `for`), what describes it (its
description, and its error once it has one), and whether it's invalid, required or disabled. A
control outside a `Field` gets `none`, and its own props.
*/

type t = {
  controlId: option<string>,
  describedBy: option<string>,
  invalid: bool,
  required: bool,
  disabled: bool,
}

let none = {controlId: None, describedBy: None, invalid: false, required: false, disabled: false}

let context = Weft.Context.make(none)

module Provider = {
  let make = Weft.Context.provider(context)
}

let use = () => Weft.Hooks.useContext(context)

/** `own`, then `field`'s: an `aria-describedby` of both, if either has one. */
let describedBy = (own: option<string>, field: option<string>) =>
  switch (own, field) {
  | (Some(own), Some(field)) => Some(`${own} ${field}`)
  | (Some(ids), None) | (None, Some(ids)) => Some(ids)
  | (None, None) => None
  }
