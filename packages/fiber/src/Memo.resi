/***
Components that skip rendering when their props haven't changed.

```rescript
module Row = {
  @jsx.component
  let make = Fiber.Memo.memo((~label: string) => <li> {TestJsx.string(label)} </li>)
}
```

`@jsx.component` only accepts a one-argument wrapper, so for `memoCustomComparison`, shadow `make`:

```rescript
module Row = {
  @jsx.component
  let make = (~label: string, ~onClick: unit => unit) => ...
  let make = Fiber.Memo.memoCustomComparison(make, (a, b) => a.label == b.label)
}
```

A memoized component still renders for its own state updates and for changes to contexts it reads.
Props are compared when its parent renders it again: with `memo`, field by field with `Object.is`
(so a new `children` element, or a new closure, counts as a change).
*/

/** `component`, skipping renders whose props are shallowly equal to the previous render's. */
let memo: JsxCore.component<'props> => JsxCore.component<'props>

/** `component`, skipping renders when `equal(previousProps, nextProps)`. */
let memoCustomComparison: (
  JsxCore.component<'props>,
  ('props, 'props) => bool,
) => JsxCore.component<'props>

/** Whether two props records have the same fields with `Object.is`-equal values. */
let shallowEqual: ('props, 'props) => bool
