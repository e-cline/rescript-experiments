/***
State a component's caller may control (`value`, with `onValueChange` told of every change) or
leave to it (starting from `defaultValue`), as Base UI's components do.
*/

/** The current value, and a setter that tells `onChange` (and keeps it, if it's uncontrolled). */
let use = (~value: option<'a>, ~defaultValue: 'a, ~onChange: option<'a => unit>) => {
  let (own, setOwn) = Weft.Hooks.useState(() => defaultValue)
  let controlled = value->Option.isSome
  let set = next => {
    if !controlled {
      setOwn(_ => next)
    }
    onChange->Option.forEach(onChange => onChange(next))
  }
  (value->Option.getOr(own), set)
}
