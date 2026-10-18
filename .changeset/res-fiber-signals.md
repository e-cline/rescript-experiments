---
'@e-cline/fiber_signals': patch
---

New package: hooks for reading `@e-cline/signals` signals from `@e-cline/fiber` components.
`SignalHooks.useSignal`, `useAtom` and `useComputed0`/`useComputed1` render a component again when
what it read changes, through `useSyncExternalStore`, so a signal change can't commit half-applied
in a transition.
