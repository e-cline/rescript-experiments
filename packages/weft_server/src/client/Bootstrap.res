type queue = {push: Nullable.t<string> => int}

@get_index external queued: ({..}, string) => Nullable.t<array<Nullable.t<string>>> = ""
@set_index external setQueue: ({..}, string, queue) => unit = ""

let rows = target => {
  let encoder = Streams.Encoder.make()
  let closed = ref(false)
  Streams.make({
    start: controller => {
      let take = row =>
        if !closed.contents {
          switch row->Nullable.toOption {
          | Some(text) => controller->Streams.enqueue(encoder->Streams.Encoder.encode(text))
          | None =>
            closed := true
            controller->Streams.close
          }
        }
      queued(target, "__weft")->Nullable.toOption->Option.forEach(rows => rows->Array.forEach(take))
      // From now on, the page's scripts push straight onto the stream.
      setQueue(
        target,
        "__weft",
        {
          push: row => {
            take(row)
            0
          },
        },
      )
    },
  })
}

@val external self: {..} = "self"
@val @scope("location") external pathname: string = "pathname"
@val @scope("location") external search: string = "search"
@val @scope("history")
external pushState: (Nullable.t<unknown>, string, string) => unit = "pushState"
@val @scope("location") external assign: string => unit = "assign"
@val @scope("location") external replace: string => unit = "replace"
@val external addEventListener: (string, unit => unit) => unit = "addEventListener"
@val external removeEventListener: (string, unit => unit) => unit = "removeEventListener"
@val external document: WeftDom.Dom.document = "document"
@send
external getElementById: (WeftDom.Dom.document, string) => Nullable.t<WeftDom.Dom.element> =
  "getElementById"
@send external getAttribute: (WeftDom.Dom.element, string) => Nullable.t<string> = "getAttribute"

let start = async (~loadModule, ~fetch=?, ~container=?, ~url=?, ~onRefresh=?, ~signal=?, ()) => {
  let client = Decoder.make(~loadModule, ~fetch?)
  let container = switch container {
  | Some(container) => container
  | None =>
    switch document->getElementById("root")->Nullable.toOption {
    | Some(container) => container
    | None => Errors.fail(17, Common.Env.isDev ? "WeftServer: the page has no #root" : "")
    }
  }
  // The server rendered the page as HTML (`Page`): hydrate it, rather than render it afresh.
  let hydrating = container->getAttribute("data-weft-html")->Nullable.toOption->Option.isSome
  let root = ref(None)
  let navigation = Navigation.make(
    client,
    ~render=element => root.contents->Option.forEach(root => root->WeftDom.Client.render(element)),
    ~url=url->Option.getOr(pathname ++ search),
    ~onNavigate=url => pushState(Nullable.null, "", url),
    // A page that can't be shown in place (its payload couldn't be fetched, or it failed) is
    // loaded the ordinary way, for the server's own answer.
    ~onFailed=(url, ~push) => push ? assign(url) : replace(url),
  )
  let onPopState = () => navigation->Navigation.load(pathname ++ search)->ignore
  addEventListener("popstate", onPopState)
  // Stopping the page: nothing of it runs any more (its effects cleaned up, its handlers gone).
  signal->Option.forEach(signal => signal->Streams.Signal.onAbort(() => {
      removeEventListener("popstate", onPopState)
      root.contents->Option.forEach(WeftDom.Client.unmount)
      root := None
    }, {once: true}))
  onRefresh->Option.forEach(onRefresh => onRefresh(() => navigation->Navigation.refresh->ignore))
  if !hydrating {
    // At once, as before: the container is emptied while the payload is still coming.
    root := Some(WeftDom.Client.createRoot(container))
  }
  let element = await client->Decoder.fromStream(rows(self))
  let stopped = signal->Option.mapOr(false, Streams.Signal.aborted)
  if stopped {
    ()
  } else if hydrating {
    // The same tree the server's HTML was rendered from: the page's context around the payload.
    root := Some(WeftDom.Client.hydrateRoot(container, Navigation.wrap(navigation, element)))
  } else {
    navigation->Navigation.show(element)
  }
  navigation
}

@val external maybeDocument: Nullable.t<WeftDom.Dom.document> = "globalThis.document"
@get external readyState: WeftDom.Dom.document => string = "readyState"
@get external documentElement: WeftDom.Dom.document => WeftDom.Dom.element = "documentElement"

type observer
type observing = {childList: bool, subtree: bool}
@new external makeObserver: (unit => unit) => observer = "MutationObserver"
@send external observe: (observer, WeftDom.Dom.element, observing) => unit = "observe"
@send external disconnect: observer => unit = "disconnect"
@send
external addDocumentListener: (WeftDom.Dom.document, string, unit => unit) => unit =
  "addEventListener"

let main = (loadModule, onRefresh) =>
  switch maybeDocument->Nullable.toOption {
  | Some(document) =>
    let rootOf = () => document->getElementById("root")->Nullable.toOption
    let begin = container => start(~loadModule, ~container, ~onRefresh, ())->ignore
    switch rootOf() {
    | Some(container) => begin(container)
    // The bootstrap's script is `async`, so it can run before the parser reaches `#root` (which
    // `Page` writes once the shell is ready): it starts once `#root` is there. (Its rows come after
    // it, so it has been parsed by the time the bootstrap has the root row.)
    | None if document->readyState == "loading" =>
      let started = ref(false)
      let observer = ref(None)
      let stop = () => observer.contents->Option.forEach(disconnect)
      let check = () =>
        switch rootOf() {
        | Some(container) if !started.contents =>
          started := true
          stop()
          begin(container)
        | _ => ()
        }
      let watching = makeObserver(check)
      observer := Some(watching)
      watching->observe(document->documentElement, {childList: true, subtree: true})
      document->addDocumentListener("DOMContentLoaded", () => {
        check()
        stop()
      })
    | None => ()
    }
  | None => ()
  }
