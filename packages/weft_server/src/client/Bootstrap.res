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
@val external addEventListener: (string, unit => unit) => unit = "addEventListener"
@val external document: WeftDom.Dom.document = "document"
@send
external getElementById: (WeftDom.Dom.document, string) => Nullable.t<WeftDom.Dom.element> =
  "getElementById"
@send external getAttribute: (WeftDom.Dom.element, string) => Nullable.t<string> = "getAttribute"

let start = async (~loadModule, ~fetch=?, ~container=?, ~url=?, ~onRefresh=?, ()) => {
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
  )
  addEventListener("popstate", () => navigation->Navigation.load(pathname ++ search)->ignore)
  onRefresh->Option.forEach(onRefresh => onRefresh(() => navigation->Navigation.refresh->ignore))
  if !hydrating {
    // At once, as before: the container is emptied while the payload is still coming.
    root := Some(WeftDom.Client.createRoot(container))
  }
  let element = await client->Decoder.fromStream(rows(self))
  if hydrating {
    // The same tree the server's HTML was rendered from: the page's context around the payload.
    root := Some(WeftDom.Client.hydrateRoot(container, Navigation.wrap(navigation, element)))
  } else {
    navigation->Navigation.show(element)
  }
  navigation
}

@val external maybeDocument: Nullable.t<WeftDom.Dom.document> = "globalThis.document"

let main = (loadModule, onRefresh) =>
  switch maybeDocument
  ->Nullable.toOption
  ->Option.flatMap(document => document->getElementById("root")->Nullable.toOption) {
  | Some(container) => start(~loadModule, ~container, ~onRefresh, ())->ignore
  | None => ()
  }
