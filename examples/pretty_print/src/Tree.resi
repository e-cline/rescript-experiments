/***
`@prettyPrint` in an interface file declares the functions that the same
annotation in the implementation defines:

```rescript
let t_toDoc: ('a => PrettyPrint.doc, t<'a>) => PrettyPrint.doc
let t_prettyPrint: ('a => PrettyPrint.doc, t<'a>) => string
```
*/

@prettyPrint
type rec t<'a> =
  | Leaf
  | Node({left: t<'a>, value: 'a, right: t<'a>})

let fromArray: array<'a> => t<'a>
