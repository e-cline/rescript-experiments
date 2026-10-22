module Element = WeftCore.Element

type t = {
  client: Decoder.t,
  render: Element.t => unit,
  mutable url: string,
  onNavigate: string => unit,
  latest: Decoder.Latest.t,
}

let context: WeftCore.Context.t<option<t>> = WeftCore.Context.make(None)
let provider = WeftCore.Context.provider(context)

let make = (client, ~render, ~url, ~onNavigate=_ => ()) => {
  client,
  render,
  url,
  onNavigate,
  latest: Decoder.Latest.make(),
}

let show = (navigation, element) =>
  navigation.render(WeftCore.JsxCore.jsx(provider, {value: Some(navigation), children: element}))

let fetchAndShow = async (navigation, url, ~push) =>
  switch await navigation.latest->Decoder.Latest.fetchElement(navigation.client, url) {
  | Some(element) =>
    navigation.url = url
    WeftCore.Transition.start(() => show(navigation, element))
    if push {
      navigation.onNavigate(url)
    }
  | None => ()
  }

let navigate = (navigation, url) => fetchAndShow(navigation, url, ~push=true)
let load = (navigation, url) => fetchAndShow(navigation, url, ~push=false)
let refresh = navigation => load(navigation, navigation.url)
let url = navigation => navigation.url
let client = navigation => navigation.client

let useNavigation = () =>
  switch WeftCore.Hooks.useContext(context) {
  | Some(navigation) => navigation
  | None =>
    Errors.fail(
      16,
      Common.Env.isDev
        ? "WeftServer: useNavigation (or useRefetchable) was called outside a page: render the element with Navigation.show"
        : "",
    )
  }

type refetchable = {
  element: Element.t,
  refetch: (~url: string=?) => promise<unit>,
  isPending: bool,
}

/** A refetched element, and the `children` it replaced (newer `children` replace it in turn). */
type refetched = {fetched: Element.t, over: Element.t}

let useRefetchable = (~src, children) => {
  open WeftCore.Hooks
  let navigation = useNavigation()
  let (refetched, setRefetched) = useState(() => None)
  let (fetching, setFetching) = useState(() => false)
  let (transitionPending, startTransition) = useTransition()
  // Each place's fetches replace each other.
  let latest = useMemo0(() => Decoder.Latest.make())
  // What `children` are now, for a refetch finishing later to record what it replaced.
  let currentChildren = useRef(children)
  currentChildren.current = children

  let refetch = useCallback2(async (~url=?) => {
    setFetching(_ => true)
    switch await latest->Decoder.Latest.fetchElement(navigation.client, url->Option.getOr(src)) {
    | Some(fetched) =>
      // In a transition, so what's on screen stays until what replaces it is ready.
      startTransition(() => {
        setFetching(_ => false)
        setRefetched(_ => Some({fetched, over: currentChildren.current}))
      })
    | None => ()
    | exception error =>
      setFetching(_ => false)
      throw(error)
    }
  }, (navigation, src))

  let element = switch refetched {
  // Shown until newer `children` come (with a `navigate` or `refresh`): whichever is newer wins.
  | Some({fetched, over}) if over === children => fetched
  | _ => children
  }
  {element, refetch, isPending: fetching || transitionPending}
}
