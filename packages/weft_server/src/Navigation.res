module Element = WeftCore.Element

/** A frame's entry in its page's registry, which `useFrame` reads. */
type registered = {
  mutable refetch: option<(~url: string=?) => promise<unit>>,
  mutable isPending: bool,
  /** Who to tell when either changes. */
  listeners: Set.t<unit => unit>,
  /** The registration currently in effect, so an older one's cleanup leaves a newer one alone. */
  mutable owner: int,
}

type t = {
  client: Client.t,
  render: Element.t => unit,
  mutable url: string,
  onNavigate: string => unit,
  latest: Client.Latest.t,
  frames: Map.t<string, registered>,
  mutable registrations: int,
}

let context: WeftCore.Context.t<option<t>> = WeftCore.Context.make(None)
let provider = WeftCore.Context.provider(context)

let make = (client, ~render, ~url, ~onNavigate=_ => ()) => {
  client,
  render,
  url,
  onNavigate,
  latest: Client.Latest.make(),
  frames: Map.make(),
  registrations: 0,
}

let show = (navigation, element) =>
  navigation.render(WeftCore.JsxCore.jsx(provider, {value: Some(navigation), children: element}))

let fetchAndShow = async (navigation, url, ~push) =>
  switch await navigation.latest->Client.Latest.fetchElement(navigation.client, url) {
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
        ? "WeftServer: useNavigation (or useFrame) was called outside a page: render the element with Navigation.show"
        : "",
    )
  }

type frame = {
  refetch: (~url: string=?) => promise<unit>,
  isPending: bool,
}

let registered = (navigation, name) =>
  switch navigation.frames->Map.get(name) {
  | Some(found) => found
  | None =>
    let found = {refetch: None, isPending: false, listeners: Set.make(), owner: -1}
    navigation.frames->Map.set(name, found)
    found
  }

let notify = found => found.listeners->Set.forEach(listener => listener())

let registerFrame = (navigation, name, ~refetch, ~isPending) => {
  let found = registered(navigation, name)
  navigation.registrations = navigation.registrations + 1
  let owner = navigation.registrations
  found.owner = owner
  found.refetch = Some(refetch)
  found.isPending = isPending
  notify(found)
  () =>
    if found.owner == owner {
      found.refetch = None
      found.isPending = false
      notify(found)
    }
}

let useFrame = name => {
  let navigation = useNavigation()
  let found = registered(navigation, name)
  let subscribe = WeftCore.Hooks.useCallback1(listener => {
    found.listeners->Set.add(listener)
    () => found.listeners->Set.delete(listener)->ignore
  }, [found])
  let isPending = WeftCore.Hooks.useSyncExternalStore(~subscribe, ~getSnapshot=() =>
    found.isPending
  )
  let refetch = WeftCore.Hooks.useCallback1((~url=?) =>
    switch found.refetch {
    | Some(refetch) => refetch(~url?)
    | None => Promise.resolve()
    }
  , [found])
  {refetch, isPending}
}

let frame = (navigation, name) => {
  let found = registered(navigation, name)
  {
    refetch: (~url=?) =>
      switch found.refetch {
      | Some(refetch) => refetch(~url?)
      | None => Promise.resolve()
      },
    isPending: found.isPending,
  }
}
