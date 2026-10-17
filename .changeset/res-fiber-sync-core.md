---
'@e-cline/res_fiber': patch
---

New package: a React-like component library in ReScript. Components are `@jsx.component` functions
rendered through ReScript's generic JSX transform (`@@jsxConfig` per file); a fiber reconciler with
React's keyed child diffing renders them synchronously, with batched updates, through any host that
implements `HostConfig.S`. Includes `useState`, `useReducer`, `useRef`, `useMemo*`, `useCallback*`,
`useEffect*`, `useLayoutEffect*`, `useContext` with `Context`, `Memo.memo`, `useSyncExternalStore`,
host `ref` props, and an in-memory `TestRenderer` that logs every host operation.
