/**
A recursive type with a type parameter. The printers generated for it take a
printer for `'a` as their first argument -- `Tree.t_prettyPrint(PrettyPrint.int, tree)`
-- and, because the type is `rec`, are defined with `let rec`.
*/
@prettyPrint
type rec t<'a> =
  | Leaf
  | Node({left: t<'a>, value: 'a, right: t<'a>})

/** A balanced tree holding `items` in order. */
let rec fromArray = items =>
  switch items {
  | [] => Leaf
  | _ =>
    let middle = Array.length(items) / 2
    Node({
      left: fromArray(items->Array.slice(~start=0, ~end=middle)),
      value: items->Array.getUnsafe(middle),
      right: fromArray(items->Array.slice(~start=middle + 1)),
    })
  }
