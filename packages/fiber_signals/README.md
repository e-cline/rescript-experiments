# @e-cline/fiber_signals

Hooks for reading [`@e-cline/signals`](../signals) atoms and computeds from
[`@e-cline/fiber`](../fiber) components: a component renders again when a signal it read through a
hook changes, and only then.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/fiber_signals @e-cline/fiber @e-cline/signals rescript @rescript/runtime
```

Add the three packages to the `dependencies` in your `rescript.json`. The module is
`FiberSignals.SignalHooks`.

## Using it

```rescript
let count = Signals.Atom.make(0)
let parity = Signals.Computed.make(() => mod(Signals.Atom.get(count), 2) == 0 ? "even" : "odd")

module Counter = {
  @jsx.component
  let make = () => {
    let (value, update) = FiberSignals.SignalHooks.useAtom(count)
    let label = FiberSignals.SignalHooks.useSignal(parity)
    <button onClick={_ => update(n => n + 1)}>
      {FiberDom.Jsx.string(`${Int.toString(value)} (${label})`)}
    </button>
  }
}
```

- **`useSignal(signal)`**: the value of any `Signal.t` (an atom via `Atom.toSignal`, or a
  `Computed`).
- **`useAtom(atom)`**: the value and an updater (`Atom.update`), stable while the atom is.
- **`useComputed0(compute)`** / **`useComputed1(compute, deps)`**: a `Computed` owned by the
  component (made on mount, or again when `deps` change), for deriving from signals and props
  together.

A computed that recomputes to an equal value doesn't render the component. Writes in one
`Batch.run`, or in one synchronous stretch of code, render once.

## How it works

Each hook is `Fiber.Hooks.useSyncExternalStore` over the signal: `getSnapshot` is `Signal.peek` (so
rendering never adds a dependency to whatever effect or computed is running), and `subscribe` is an
`EffectBase` effect on `Scheduler.Sync` that reads the signal and, after its first run, reports each
change. So signal changes get the store hook's guarantees: they render at sync priority, and one
that lands while a transition is paused makes it render again rather than commit a mix of old and
new values.

The one caveat comes from `signals`' effect ownership: an effect created while another effect's
function is running belongs to that run. Subscriptions are created in `useEffect`; if one of your
own signal effects renders synchronously (calling `flushSync` or `act` in its body), the components
mounted by that render subscribe from inside it, and their subscriptions end when it reruns.
