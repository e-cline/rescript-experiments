module Element = Weft.Element

type t = {
  client: Decoder.t,
  render: Element.t => unit,
  mutable url: string,
  onNavigate: string => unit,
  /** What to do instead when `navigate` or `load` can't show a URL's payload, if anything. */
  onFailed: option<(string, ~push: bool) => unit>,
  latest: Decoder.Latest.t,
  /** The server's page, which an HTML render reads: it can't fetch anything. */
  onServer: bool,
}

let context: Weft.Context.t<option<t>> = Weft.Context.make(None)
let provider = Weft.Context.provider(context)

let make = (client, ~render, ~url, ~onNavigate=_ => (), ~onFailed=?) => {
  client,
  render,
  url,
  onNavigate,
  onFailed,
  latest: Decoder.Latest.make(),
  onServer: false,
}

let makeForServer = (client, ~url) => {
  client,
  render: _ => (),
  url,
  onNavigate: _ => (),
  onFailed: None,
  latest: Decoder.Latest.make(),
  onServer: true,
}

let checkOnClient = navigation =>
  if navigation.onServer {
    Errors.fail(
      20,
      Common.Env.isDev
        ? "WeftServer: the page was asked to fetch while it was rendered on the server (navigate, refresh, or a refetch): call these from handlers and effects, which only run in the browser"
        : "",
    )
  }

let wrap = (navigation, element) =>
  Weft.JsxCore.jsx(provider, {value: Some(navigation), children: element})

let show = (navigation, element) => navigation.render(wrap(navigation, element))

let fetchAndShowOnClient = async (navigation, url, ~push, ~canFallBack) =>
  switch await navigation.latest->Decoder.Latest.fetchElement(navigation.client, url) {
  | Some(element) =>
    navigation.url = url
    Weft.Transition.start(() => show(navigation, element))
    if push {
      navigation.onNavigate(url)
    }
  | None => ()
  | exception error =>
    switch navigation.onFailed {
    | Some(onFailed) if canFallBack => onFailed(url, ~push)
    | _ => throw(error)
    }
  }

// Not `async`, so that on the server the refusal is thrown where it's asked for, not as a
// rejection nobody waits on.
let fetchAndShow = (navigation, url, ~push, ~canFallBack) => {
  checkOnClient(navigation)
  fetchAndShowOnClient(navigation, url, ~push, ~canFallBack)
}

let navigate = (navigation, url) => fetchAndShow(navigation, url, ~push=true, ~canFallBack=true)
let load = (navigation, url) => fetchAndShow(navigation, url, ~push=false, ~canFallBack=true)
// What's on screen stays, rather than being thrown away for a page load: the caller hears why.
let refresh = navigation =>
  fetchAndShow(navigation, navigation.url, ~push=false, ~canFallBack=false)
let url = navigation => navigation.url
let client = navigation => navigation.client

// Following links

@get external defaultPrevented: WeftDom.Dom.event => bool = "defaultPrevented"
@get external button: WeftDom.Dom.event => Nullable.t<int> = "button"
@get external metaKey: WeftDom.Dom.event => bool = "metaKey"
@get external ctrlKey: WeftDom.Dom.event => bool = "ctrlKey"
@get external shiftKey: WeftDom.Dom.event => bool = "shiftKey"
@get external altKey: WeftDom.Dom.event => bool = "altKey"
@get
external eventCurrentTarget: WeftDom.Dom.event => Nullable.t<WeftDom.Dom.element> = "currentTarget"
@send
external getAttribute: (WeftDom.Dom.element, string) => Nullable.t<string> = "getAttribute"
@send external hasAttribute: (WeftDom.Dom.element, string) => bool = "hasAttribute"

type parsedUrl = {origin: string, pathname: string, search: string, hash: string}
@new external parseUrl: (string, string) => parsedUrl = "URL"
@val @scope("location") external locationHref: string = "href"

let staysInPage = (event, ~href, ~from) => {
  let link = eventCurrentTarget(event)->Nullable.toOption
  let attribute = name => link->Option.flatMap(link => getAttribute(link, name)->Nullable.toOption)
  let plainClick =
    !defaultPrevented(event) &&
    button(event)->Nullable.toOption->Option.getOr(0) == 0 &&
    !metaKey(event) &&
    !ctrlKey(event) &&
    !shiftKey(event) &&
    !altKey(event)
  let ownWindow = switch attribute("target") {
  | None | Some("") | Some("_self") => true
  | Some(_) => false
  }
  let download = link->Option.mapOr(false, link => link->hasAttribute("download"))
  plainClick &&
  ownWindow &&
  !download &&
  switch (parseUrl(href, from), parseUrl(from, from)) {
  | (target, current) =>
    target.origin == current.origin &&
      // A link to a part of this page (`#comments`) scrolls there, as the browser does it.
      !(target.pathname == current.pathname && target.search == current.search && target.hash != "")
  | exception _ => false
  }
}

let followLink = (navigation, event, ~href) =>
  if staysInPage(event, ~href, ~from=locationHref) {
    WeftDom.Dom.Event.preventDefault(event)
    navigate(navigation, href)
  } else {
    Promise.resolve()
  }

let useNavigation = () =>
  switch Weft.Hooks.useContext(context) {
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
  open Weft.Hooks
  let navigation = useNavigation()
  let (refetched, setRefetched) = useState(() => None)
  let (fetching, setFetching) = useState(() => false)
  let (transitionPending, startTransition) = useTransition()
  // Each place's fetches replace each other.
  let latest = useMemo0(() => Decoder.Latest.make())
  // What `children` are now, for a refetch finishing later to record what it replaced.
  let currentChildren = useRef(children)
  currentChildren.current = children

  let refetchOnClient = async (~url=?) => {
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
  }
  let refetch = useCallback2((~url=?) => {
    checkOnClient(navigation)
    refetchOnClient(~url?)
  }, (navigation, src))

  let element = switch refetched {
  // Shown until newer `children` come (with a `navigate` or `refresh`): whichever is newer wins.
  | Some({fetched, over}) if over === children => fetched
  | _ => children
  }
  {element, refetch, isPending: fetching || transitionPending}
}
