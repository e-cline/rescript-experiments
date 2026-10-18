/***
Hooks that read `signals` signals from `weft_core` components, rendering them again when what
they read changes.

```rescript
let count = Signals.Atom.make(0)
let doubled = Signals.Computed.make(() => Signals.Atom.get(count) * 2)

@jsx.component
let make = () => {
  let (value, setCount) = WeftSignals.SignalHooks.useAtom(count)
  let twice = WeftSignals.SignalHooks.useSignal(doubled)
  ...
}
```

Each hook subscribes with an `EffectBase` effect on `Scheduler.Sync`, so a write is noticed as soon
as it lands (or when the outermost `Batch.run` ends), and the component renders in the next flush,
together with everything else updated in the same task. A render only reads the current value
(`Signal.peek`), so it never adds dependencies to an effect or computed that happens to be running.

They're built on `WeftCore.Hooks.useSyncExternalStore`: a signal that changes while a transition is
paused partway can't commit with some components showing its old value and some its new one.

Read signals with these hooks, not `Signal.get` in a component's body: a component only renders
again for the signals a hook subscribed to.

One caveat comes from `signals`' effect ownership: an effect created while another effect's
function runs belongs to that run. Subscriptions are made in `useEffect`, so if one of your own
signal effects renders synchronously (calling `flushSync` or `act` in its body), the subscriptions
of components mounted then belong to that effect, and stop when it reruns.
*/

/** The signal's current value. */
let useSignal: Signals.Signal.t<'value, 'diff> => 'value

/**
The atom's current value, and a function that updates it (`Atom.update`). The updater keeps its
identity while the atom does.
*/
let useAtom: Signals.Atom.t<'value, 'diff> => ('value, ('value => 'value) => unit)

/**
The value of a `Computed` of `compute`, created on mount and kept. `compute` reads signals with
`Signal.get`/`Atom.get` (tracked) like any `Computed`, and the component renders when its value
changes (by `Object.is`, or `~equal`).
*/
let useComputed0: (~equal: ('value, 'value) => bool=?, unit => 'value) => 'value

/** `useComputed0`, with the `Computed` made afresh whenever `deps` change. */
let useComputed1: (~equal: ('value, 'value) => bool=?, unit => 'value, array<'a>) => 'value
