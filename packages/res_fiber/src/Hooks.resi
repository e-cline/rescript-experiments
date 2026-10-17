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

/**
Runs `effect` after the commit that first renders the component, and again after every commit where
`deps` changed, after the previous run's cleanup (the function `effect` returned, if any). The last
cleanup runs when the component is removed. Effects run after the browser can paint, so they don't
delay showing the update. `useEffect` (no deps) runs after every commit.
*/
let useEffect: (unit => option<unit => unit>) => unit
let useEffect0: (unit => option<unit => unit>) => unit
let useEffect1: (unit => option<unit => unit>, array<'a>) => unit
let useEffect2: (unit => option<unit => unit>, ('a, 'b)) => unit
let useEffect3: (unit => option<unit => unit>, ('a, 'b, 'c)) => unit
let useEffect4: (unit => option<unit => unit>, ('a, 'b, 'c, 'd)) => unit
let useEffect5: (unit => option<unit => unit>, ('a, 'b, 'c, 'd, 'e)) => unit

/**
Like the `useEffect` family, but runs synchronously right after the host is updated, before the
commit returns: for reading layout or adjusting it before anything is shown. An update made here
renders before control returns.
*/
let useLayoutEffect: (unit => option<unit => unit>) => unit
let useLayoutEffect0: (unit => option<unit => unit>) => unit
let useLayoutEffect1: (unit => option<unit => unit>, array<'a>) => unit
let useLayoutEffect2: (unit => option<unit => unit>, ('a, 'b)) => unit
let useLayoutEffect3: (unit => option<unit => unit>, ('a, 'b, 'c)) => unit
let useLayoutEffect4: (unit => option<unit => unit>, ('a, 'b, 'c, 'd)) => unit
let useLayoutEffect5: (unit => option<unit => unit>, ('a, 'b, 'c, 'd, 'e)) => unit

/**
The value of the nearest `Context.provider` above, or the context's default. The component renders
again when that value changes. Unlike the other hooks, this one may be called conditionally.
*/
let useContext: Context.t<'value> => 'value

/**
A value read from a store outside the tree. `getSnapshot` returns the current value (the same value,
by `Object.is`, until the store changes); `subscribe` registers a listener for changes and returns a
function that unregisters it. The component renders again whenever the snapshot changes.
`subscribe` is called again whenever its identity changes, so define it outside the component or
memoize it.
*/
let useSyncExternalStore: (
  ~subscribe: (unit => unit) => unit => unit,
  ~getSnapshot: unit => 'snapshot,
) => 'snapshot

/**
`(isPending, startTransition)`. `startTransition(f)` is `Transition.start(f)`, plus `isPending`:
`true` from an urgent render straight away, until the transition's render commits. `startTransition`
keeps its identity.
*/
let useTransition: unit => (bool, (unit => unit) => unit)

/**
`value`, a step behind when it changes in an urgent render: that render returns the previous value,
and a transition renders the component again with the new one. For keeping an expensive part of the
page (results for a search box's text, say) from slowing down the part that must respond at once.
*/
let useDeferredValue: 'value => 'value
