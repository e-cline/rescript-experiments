---
'@e-cline/res_fiber': patch
---

New package: a React-like component library in ReScript. Components are `@jsx.component` functions
rendered through ReScript's generic JSX transform (`@@jsxConfig` per file); a fiber reconciler with
React's keyed child diffing renders them, with batched updates, through any host that implements
`HostConfig.S`. Transitions (`Transition.start`, `useTransition`, `useDeferredValue`) render in time
slices on a pluggable `Scheduler.S`, are interrupted by urgent updates, and keep skipped updates in
order. Includes `useState`, `useReducer`, `useRef`, `useMemo*`, `useCallback*`, `useEffect*`,
`useLayoutEffect*`, `useContext` with `Context`, `Memo.memo`, `useSyncExternalStore`, host `ref`
props, `ErrorBoundary`, `Portal`, `Suspense` with `Hooks.use`, and an in-memory `TestRenderer` that
logs every host operation.
