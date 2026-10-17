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
