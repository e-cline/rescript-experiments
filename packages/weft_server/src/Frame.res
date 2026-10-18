@@directive("'use weft entrypoint'")

type props = {name: string, src: string, children: WeftCore.Element.t}

/** A refetched element, and the `children` it replaced (newer `children` replace it in turn). */
type refetched = {element: WeftCore.Element.t, over: WeftCore.Element.t}

let make = ({name, src, children}: props) => {
  open WeftCore.Hooks
  let navigation = Navigation.useNavigation()
  let (refetched, setRefetched) = useState(() => None)
  let (fetching, setFetching) = useState(() => false)
  let (transitionPending, startTransition) = useTransition()
  let latest = useMemo0(() => Client.Latest.make())
  // What `children` are now, for a refetch finishing later to record what it replaced.
  let currentChildren = useRef(children)
  currentChildren.current = children

  let refetch = useCallback2(async (~url=?) => {
    setFetching(_ => true)
    switch await latest->Client.Latest.fetchElement(
      navigation->Navigation.client,
      url->Option.getOr(src),
    ) {
    | Some(element) =>
      startTransition(() => {
        setFetching(_ => false)
        setRefetched(_ => Some({element, over: currentChildren.current}))
      })
    | None => ()
    | exception error =>
      setFetching(_ => false)
      throw(error)
    }
  }, (navigation, src))

  let isPending = fetching || transitionPending
  useLayoutEffect4(
    () => Some(navigation->Navigation.registerFrame(name, ~refetch, ~isPending)),
    (navigation, name, refetch, isPending),
  )

  switch refetched {
  | Some({element, over}) if over === children => element
  | _ => children
  }
}

WeftCore.Entrypoint.mark(make, "@e-cline/weft_server/src/Frame.res#")
