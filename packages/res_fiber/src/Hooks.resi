/***
Hooks: state and memoization for function components, named as in `@rescript/react`.

Call them only while a component renders, unconditionally and in the same order every time; the
reconciler matches each call to the one in the previous render by position, and throws if the order
changes.

Dependencies (`useMemo1`'s array, `useMemo2`'s tuple, ...) are compared element by element with
`Object.is`. The `0` variants compute once, on mount.
*/

/**
State, initialised by calling `init` on mount. The setter takes a function from the current state to
the new one, and keeps its identity for the component's lifetime. Setting a state equal (by
`Object.is`) to the current one renders nothing.
*/
let useState: (unit => 'state) => ('state, ('state => 'state) => unit)

/** State updated by dispatching actions to `reducer`. `dispatch` keeps its identity. */
let useReducer: (('state, 'action) => 'state, 'state) => ('state, 'action => unit)

/** Like `useReducer`, with the initial state computed by `init` on mount. */
let useReducerWithMapState: (
  ('state, 'action) => 'state,
  'init,
  'init => 'state,
) => ('state, 'action => unit)

/** A box created on mount and kept, unchanged, for the component's lifetime. */
let useRef: 'value => Ref.t<'value>

let useMemo0: (unit => 'value) => 'value
let useMemo1: (unit => 'value, array<'a>) => 'value
let useMemo2: (unit => 'value, ('a, 'b)) => 'value
let useMemo3: (unit => 'value, ('a, 'b, 'c)) => 'value
let useMemo4: (unit => 'value, ('a, 'b, 'c, 'd)) => 'value
let useMemo5: (unit => 'value, ('a, 'b, 'c, 'd, 'e)) => 'value

let useCallback0: 'f => 'f
let useCallback1: ('f, array<'a>) => 'f
let useCallback2: ('f, ('a, 'b)) => 'f
let useCallback3: ('f, ('a, 'b, 'c)) => 'f
let useCallback4: ('f, ('a, 'b, 'c, 'd)) => 'f
let useCallback5: ('f, ('a, 'b, 'c, 'd, 'e)) => 'f
