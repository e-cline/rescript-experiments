// Tuples are JS arrays at runtime, so every dependency list is an `array<unknown>`.
external deps: 'tuple => array<unknown> = "%identity"

let basicStateReducer = (state, update) => update(state)

let useState = init => HookImpl.useReducerWith(~kind=State, ~eager=true, basicStateReducer, init)

let useReducer = (reducer, initial) =>
  HookImpl.useReducerWith(~kind=Reducer, ~eager=false, reducer, () => initial)

let useReducerWithMapState = (reducer, initial, init) =>
  HookImpl.useReducerWith(~kind=Reducer, ~eager=false, reducer, () => init(initial))

let useRef = HookImpl.useRef

let useMemo0 = create => HookImpl.useMemo(create, Some([]))
let useMemo1 = (create, a) => HookImpl.useMemo(create, Some(deps(a)))
let useMemo2 = (create, a) => HookImpl.useMemo(create, Some(deps(a)))
let useMemo3 = (create, a) => HookImpl.useMemo(create, Some(deps(a)))
let useMemo4 = (create, a) => HookImpl.useMemo(create, Some(deps(a)))
let useMemo5 = (create, a) => HookImpl.useMemo(create, Some(deps(a)))

let useCallback0 = f => HookImpl.useMemo(() => f, Some([]))
let useCallback1 = (f, a) => HookImpl.useMemo(() => f, Some(deps(a)))
let useCallback2 = (f, a) => HookImpl.useMemo(() => f, Some(deps(a)))
let useCallback3 = (f, a) => HookImpl.useMemo(() => f, Some(deps(a)))
let useCallback4 = (f, a) => HookImpl.useMemo(() => f, Some(deps(a)))
let useCallback5 = (f, a) => HookImpl.useMemo(() => f, Some(deps(a)))

let effect = (~effectKind, create, deps) => HookImpl.useEffectWith(~effectKind, create, deps)

let useEffect = create => effect(~effectKind=Passive, create, None)
let useEffect0 = create => effect(~effectKind=Passive, create, Some([]))
let useEffect1 = (create, a) => effect(~effectKind=Passive, create, Some(deps(a)))
let useEffect2 = (create, a) => effect(~effectKind=Passive, create, Some(deps(a)))
let useEffect3 = (create, a) => effect(~effectKind=Passive, create, Some(deps(a)))
let useEffect4 = (create, a) => effect(~effectKind=Passive, create, Some(deps(a)))
let useEffect5 = (create, a) => effect(~effectKind=Passive, create, Some(deps(a)))

let useLayoutEffect = create => effect(~effectKind=Layout, create, None)
let useLayoutEffect0 = create => effect(~effectKind=Layout, create, Some([]))
let useLayoutEffect1 = (create, a) => effect(~effectKind=Layout, create, Some(deps(a)))
let useLayoutEffect2 = (create, a) => effect(~effectKind=Layout, create, Some(deps(a)))
let useLayoutEffect3 = (create, a) => effect(~effectKind=Layout, create, Some(deps(a)))
let useLayoutEffect4 = (create, a) => effect(~effectKind=Layout, create, Some(deps(a)))
let useLayoutEffect5 = (create, a) => effect(~effectKind=Layout, create, Some(deps(a)))

// `Context.t` is abstract outside `Context`; it's a `ContextImpl.t`.
external contextImpl: Context.t<'value> => ContextImpl.t<'value> = "%identity"

let useContext = context => HookImpl.useContext(contextImpl(context))

type store<'snapshot> = {
  mutable value: 'snapshot,
  mutable getSnapshot: unit => 'snapshot,
}

let useSyncExternalStore = (~subscribe, ~getSnapshot) => {
  let value = getSnapshot()
  let (_, forceRender) = useReducer((count, ()) => count + 1, 0)
  let store = useRef({value, getSnapshot})
  let changed = () => !Object.is(store.current.getSnapshot(), store.current.value)
  // Keep the latest snapshot for the subscription to compare with, and catch a change made between
  // rendering and now.
  useLayoutEffect3(() => {
    store.current.value = value
    store.current.getSnapshot = getSnapshot
    if changed() {
      forceRender()
    }
    None
  }, (subscribe, value, getSnapshot))
  useEffect1(() => {
    if changed() {
      forceRender()
    }
    Some(
      subscribe(() =>
        if changed() {
          forceRender()
        }
      ),
    )
  }, [subscribe])
  value
}
