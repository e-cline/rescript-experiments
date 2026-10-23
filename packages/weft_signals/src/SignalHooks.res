module Signal = Signals.Signal
module Atom = Signals.Atom
module Computed = Signals.Computed
module EffectBase = Signals.EffectBase
module Hooks = Weft.Hooks

/**
Calls `onChange` after each change to `signal`, until the returned function is called: an effect
that reads it (which tracks it), and skips the first, immediate run.
*/
let subscribe = (signal: Signal.t<'value, 'diff>, onChange: unit => unit) => {
  let first = ref(true)
  let effect = EffectBase.make(~scheduler=Signals.Scheduler.Sync.schedule, () => {
    Signal.get(signal)->ignore
    if first.contents {
      first := false
    } else {
      onChange()
    }
  })
  () => EffectBase.dispose(effect)
}

let useSignal = (signal: Signal.t<'value, 'diff>): 'value => {
  let subscribe = Hooks.useCallback1(onChange => subscribe(signal, onChange), [signal])
  let getSnapshot = Hooks.useCallback1(() => Signal.peek(signal), [signal])
  Hooks.useSyncExternalStore(~subscribe, ~getSnapshot)
}

let useAtom = (atom: Atom.t<'value, 'diff>) => {
  let value = useSignal(Atom.toSignal(atom))
  let update = Hooks.useCallback1(f => Atom.update(atom, f), [atom])
  (value, update)
}

let useComputed0 = (~equal=?, compute: unit => 'value): 'value =>
  useSignal(Hooks.useMemo0(() => Computed.make(~equal?, compute)))

let useComputed1 = (~equal=?, compute: unit => 'value, deps: array<'a>): 'value =>
  useSignal(Hooks.useMemo1(() => Computed.make(~equal?, compute), deps))
