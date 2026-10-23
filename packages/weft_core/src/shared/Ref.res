/***
A mutable box that keeps its identity across renders, as `Hooks.useRef` returns. The field is
`current`, as in React, so the same record can later receive host instances from a `ref` prop.
*/

type t<'value> = {mutable current: 'value}
