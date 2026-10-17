@@jsxConfig({version: 4, module_: "ResFiberDom.Jsx"})

/***
An app using every public feature of `res_fiber` and `res_fiber_dom`, for `vp run size`: every kind
of hook, context, `Memo`, `ErrorBoundary`, `Suspense`, transitions, portals, `flushSync` and
`unmount`, each once. What it bundles is about the most an app can pull in from the two packages.
It's only bundled, never run.
*/

open ResFiber.Hooks

module Dom = ResFiberDom.Dom
module Jsx = ResFiberDom.Jsx

module Theme = {
  let context = ResFiber.Context.make("light")
  module Provider = {
    let make = ResFiber.Context.provider(context)
  }
}

let subscribe = _listener => () => ()
let getSnapshot = () => 0
let greeting = Promise.resolve("hello")

module Greeting = {
  @jsx.component
  let make = () => Jsx.string(use(greeting))
}

module Label = {
  @jsx.component
  let make = ResFiber.Memo.memo((~text: string) => <span> {Jsx.string(text)} </span>)
}

module App = {
  @jsx.component
  let make = (~layer: Dom.element) => {
    let (count, setCount) = useState(() => 0)
    let (total, dispatch) = useReducer((total, n) => total + n, 0)
    let button = useRef(Nullable.null)
    let theme = useContext(Theme.context)
    let doubled = useMemo1(() => count * 2, [count])
    let increment = useCallback1(_ => setCount(count => count + 1), [setCount])
    let (isPending, startTransition) = useTransition()
    let deferred = useDeferredValue(total)
    let stored = useSyncExternalStore(~subscribe, ~getSnapshot)
    useEffect1(() => {
      dispatch(count)
      None
    }, [count])
    useLayoutEffect0(() => {
      button.current->Nullable.forEach(Dom.focus)
      None
    })
    <div className=theme>
      <button ref=button onClick=increment> {Jsx.int(doubled)} </button>
      <button onClick={_ => startTransition(() => dispatch(1))}>
        {Jsx.string(isPending ? "..." : Int.toString(deferred + stored))}
      </button>
      <button onClick={_ => ResFiber.Transition.start(() => setCount(_ => 0))}>
        <Label text="reset" />
      </button>
      <ResFiber.ErrorBoundary
        fallback={(~error, ~reset as _) => Jsx.string(ResFiber.ErrorBoundary.message(error))}
      >
        <ResFiber.Suspense fallback={Jsx.string("loading")}>
          <Greeting />
        </ResFiber.Suspense>
      </ResFiber.ErrorBoundary>
      <ResFiberDom.Portal container=layer> {Jsx.string("portal")} </ResFiberDom.Portal>
    </div>
  }
}

switch Nullable.toOption(Dom.document->Dom.body->Dom.querySelector("#app")) {
| Some(container) =>
  let root = ResFiberDom.Client.createRoot(container)
  ResFiberDom.Client.flushSync(() =>
    root->ResFiberDom.Client.render(
      <Theme.Provider value="dark">
        <App layer={Dom.document->Dom.body} />
      </Theme.Provider>,
    )
  )
  ResFiberDom.Client.unmount(root)
| None => ()
}
