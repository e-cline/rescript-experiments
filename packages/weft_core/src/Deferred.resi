/***
A promise settled from outside, whose outcome `Hooks.use` and `Lazy` elements can read the moment
it's settled.

An ordinary promise's outcome can only be learned asynchronously, so `Hooks.use` records it on the
promise in a `then` callback, a microtask later, and a render that comes first suspends once to wait
for it. That's fine for data a component waits for, but not for data that has, in fact, already
arrived: a streamed server payload (`weft_server`) decodes each row as it comes in, and a render
right after that shouldn't suspend on a row it has. A `Deferred.t`'s outcome is recorded the moment
`resolve` or `reject` is called.

```rescript
let row = WeftCore.Deferred.make()
let element = WeftCore.Lazy.fromPromise(row.promise)
row.resolve(<p> {Jsx.string("arrived")} </p>)
// Rendering `element` now shows the paragraph straight away.
```
*/

type t<'value> = {
  promise: promise<'value>,
  /** Fulfils `promise` with a value. Does nothing once it has settled. */
  resolve: 'value => unit,
  /** Rejects `promise` with an error. Does nothing once it has settled. */
  reject: JsError.t => unit,
}

/**
A pending promise, and the functions that settle it. A rejection nobody waits for isn't reported as
unhandled: the error goes to whatever reads the promise (`Hooks.use`, a `Lazy` element).
*/
let make: unit => t<'value>

/** Whether `deferred` has been settled. */
let isSettled: t<'value> => bool
