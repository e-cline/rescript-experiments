@@directive("'use weft server'")

type assets = {
  scripts: array<string>,
  preloads: array<string>,
  styles: array<string>,
  entrypoints: dict<array<string>>,
  loadModule?: Decoder.loadModule,
  sheets?: dict<Render.sheet>,
  entrypointSheets?: dict<array<string>>,
}

/** The stylesheets `Render` sends, if the app has any. */
let stylesOf = (assets): option<Render.styles> =>
  assets.sheets->Option.map(sheets => {
    Render.sheets,
    entrypoints: assets.entrypointSheets->Option.getOr(dict{}),
  })

/** `text` for HTML text or a quoted attribute. */
let escape = text =>
  text
  ->String.replaceAll("&", "&amp;")
  ->String.replaceAll("<", "&lt;")
  ->String.replaceAll(">", "&gt;")
  ->String.replaceAll(`"`, "&quot;")
  ->String.replaceAll("'", "&#39;")

let rowScript = row => {
  // JSON is JavaScript, but `</script>` (or `<!--`) in a string would still end the script, and the
  // line separators U+2028 and U+2029 were once not allowed in strings: none of them get through.
  let argument = switch row {
  | Some(text) =>
    JSON.stringify(JSON.String(text))
    ->String.replaceAll("<", "\\u003c")
    ->String.replaceAll(" ", "\\u2028")
    ->String.replaceAll(" ", "\\u2029")
  | None => "null"
  }
  `<script>(self.__weft||=[]).push(${argument})</script>`
}

@get_index external jsonField: (JSON.t, string) => Nullable.t<JSON.t> = ""

let tags = (urls, tag) => urls->Array.map(tag)->Array.join("")

/** The head, but for its end (`headEnd`), which a page with HTML holds back until its shell's ready. */
let headStart = (assets, ~title, ~head, ~recordEvents=false) =>
  `<!doctype html><html lang="en"><head><meta charset="utf-8">` ++
  (// Before the shell: what's clicked or typed before it hydrates is replayed once it has.
  recordEvents ? `<script>${WeftDom.Html.eventRuntime}</script>` : "") ++
  `<meta name="viewport" content="width=device-width, initial-scale=1">` ++
  title->Option.mapOr("", title => `<title>${escape(title)}</title>`) ++
  assets.styles->tags(url => `<link rel="stylesheet" href="${escape(url)}">`) ++
  assets.preloads->tags(url => `<link rel="modulepreload" href="${escape(url)}">`) ++
  // `async`, so the bootstrap runs once it's loaded, not once the whole page has streamed in.
  assets.scripts->tags(url => `<script type="module" async src="${escape(url)}"></script>`) ++
  head->Option.getOr("")

let headEnd = `</head><body>`

/**
The URLs of the stylesheets `markup` (a segment's HTML) needs: those its class names are in, and
what they depend on, before them.
*/
let stylesheetsIn = (styles: Render.styles, markup) => {
  let hrefs = []
  let seen = Set.make()
  let rec add = id =>
    if !(seen->Set.has(id)) {
      seen->Set.add(id)
      switch styles.sheets->Dict.get(id) {
      | Some({href, dependencies}) =>
        dependencies->Array.forEach(add)
        hrefs->Array.push(href)
      | None => ()
      }
    }
  WeftCss.SheetId.inText(markup)->Array.forEach(add)
  hrefs
}

/** A `C` row's URL. */
let hrefOf = (row: Payload.row) =>
  switch row.tag {
  | Stylesheet => jsonField(row.json, "href")->Nullable.toOption->Option.flatMap(JSON.Decode.string)
  | _ => None
  }

/**
A preload for a `C` row's sheet, written after the shell: the download starts as soon as the server
knows it's needed, while the boundary's content is still rendering. Its swap links it.
*/
let stylesheetPreload = row =>
  hrefOf(row)->Option.mapOr("", href => `<link rel="preload" as="style" href="${escape(href)}">`)

/** The stylesheet links for the `C` rows in `rows`. */
let sheetLinks = (rows: array<Payload.row>) =>
  rows
  ->Array.filterMap(row =>
    hrefOf(row)->Option.map(href => `<link rel="stylesheet" href="${escape(href)}">`)
  )
  ->Array.join("")

/** `#root`, with the shell's HTML in it if there is one (`data-weft-html` says so to the bootstrap). */
let root = shell =>
  switch shell {
  | Some(shell) => `<div id="root" data-weft-html="">${shell}</div>`
  | None => `<div id="root"></div>`
  }

let tail = rowScript(None) ++ "</body></html>"

/** The entrypoint file an `E` row refers to. */
let entrypointFile = (row: Payload.row) =>
  switch row.tag {
  | EntrypointRef =>
    jsonField(row.json, "id")
    ->Nullable.toOption
    ->Option.flatMap(JSON.Decode.string)
    ->Option.map(id => id->String.split("#")->Array.getUnsafe(0))
  | _ => None
  }

/** The modulepreload links for the chunks of `row`'s entrypoint file, the first time it's seen. */
let preloads = (assets, preloaded: Set.t<string>, row: Payload.row) =>
  switch entrypointFile(row) {
  | Some(file) if !(preloaded->Set.has(file)) =>
    preloaded->Set.add(file)
    assets.entrypoints
    ->Dict.get(file)
    ->Option.getOr([])
    ->Array.map(url => `<link rel="modulepreload" href="${escape(url)}">`)
    ->Array.join("")
  | _ => ""
  }

/** Today's page: an empty `#root`, and the rows, for the client to render. */
let rowsOnly = (element, ~assets, ~title, ~head as extra, ~onError, ~signal) => {
  let payload = Render.toStream(element, ~onError?, ~signal?, ~styles=?stylesOf(assets))
  let reader = payload->Streams.getReader
  let decoder = Streams.Decoder.make()
  let encoder = Streams.Encoder.make()
  let parser = Payload.Parser.make()
  let preloaded = Set.make()
  let html = (row: Payload.row) =>
    preloads(assets, preloaded, row) ++ rowScript(Some(Payload.rowToString(row)))
  Streams.make({
    start: controller =>
      controller->Streams.enqueue(
        encoder->Streams.Encoder.encode(
          headStart(assets, ~title, ~head=extra) ++ headEnd ++ root(None),
        ),
      ),
    pull: async controller => {
      switch await reader->Streams.Reader.read {
      | {done: false, value} =>
        let rows =
          parser->Payload.Parser.push(decoder->Streams.Decoder.decode(value, {stream: true}))
        if Array.length(rows) > 0 {
          controller->Streams.enqueue(
            encoder->Streams.Encoder.encode(rows->Array.map(html)->Array.join("")),
          )
        }
      | _ =>
        controller->Streams.enqueue(encoder->Streams.Encoder.encode(tail))
        controller->Streams.close
      | exception _ =>
        // The payload failed (or was aborted): the page ends, and the client fails the rows that
        // never came.
        controller->Streams.enqueue(encoder->Streams.Encoder.encode(tail))
        controller->Streams.close
      }
    },
    cancel: _ => reader->Streams.Reader.cancel->Promise.catch(_ => Promise.resolve())->ignore,
  })
}

@send external tee: Streams.t => (Streams.t, Streams.t) = "tee"
external toHtmlSignal: Streams.Signal.t => WeftDom.Html.signal = "%identity"
external htmlStreamToStreams: WeftDom.Html.stream => Streams.t = "%identity"

let defaultOnError = error => {
  Console.error(error)
  None
}

/**
The page with its HTML: the payload rendered once, its rows written to the page for the client and
decoded on the server too, as the browser will, for `WeftDom.Html` to render. The rows wait until the
shell is written, then follow as they come, with each boundary's segment as the HTML renderer has it.
*/
let withHtml = (element, ~assets, ~loadModule, ~url, ~title, ~head as extra, ~onError, ~signal) => {
  let onError = onError->Option.getOr(defaultOnError)
  // An error the payload carried was reported when its row was written: its digest, not again.
  let htmlOnError = error =>
    switch Decoder.reportedDigest(error) {
    | Some(digest) => digest
    | None => onError(error)
    }
  let (forPage, forHtml) =
    Render.toStream(element, ~onError, ~signal?, ~styles=?stylesOf(assets))->tee
  // The server waits for no stylesheet (there's no document to show anything in), even in a process
  // that has one (a test's).
  let decoder = Decoder.make(~loadModule, ~loadSheet=_ => None)
  let navigation = Navigation.makeForServer(decoder, ~url)
  let encoder = Streams.Encoder.make()
  let output = ref(None)
  let closed = ref(false)
  let write = text =>
    if !closed.contents {
      output.contents->Option.forEach(controller =>
        controller->Streams.enqueue(encoder->Streams.Encoder.encode(text))
      )
    }
  let preloaded = Set.make()
  let rowHtml = (row: Payload.row) =>
    preloads(assets, preloaded, row) ++
    stylesheetPreload(row) ++
    rowScript(Some(Payload.rowToString(row)))
  // Until the shell is written, the rows wait.
  let held: ref<option<array<Payload.row>>> = ref(Some([]))
  let rowsDone = ref(false)
  let htmlDone = ref(false)
  let finishIfDone = () =>
    if rowsDone.contents && htmlDone.contents && !closed.contents {
      write(tail)
      closed := true
      output.contents->Option.forEach(Streams.close)
    }
  let writeShell = shell =>
    switch held.contents {
    | Some(rows) =>
      held := None
      // The head's end, now the shell's ready: the sheets the rows so far need (so the shell never
      // shows without its styles: stylesheets in the head block rendering), and the chunks of its
      // entrypoints, loading while the HTML parses.
      let links =
        sheetLinks(rows) ++ rows->Array.map(row => preloads(assets, preloaded, row))->Array.join("")
      let rest = rows->Array.map(row => rowScript(Some(Payload.rowToString(row))))->Array.join("")
      write(links ++ headEnd ++ root(shell) ++ rest)
    | None => ()
    }
  let pumpRows = async () => {
    let reader = forPage->Streams.getReader
    let decoder = Streams.Decoder.make()
    let parser = Payload.Parser.make()
    let finished = ref(false)
    while !finished.contents {
      switch await reader->Streams.Reader.read {
      | {done: false, value} =>
        parser
        ->Payload.Parser.push(decoder->Streams.Decoder.decode(value, {stream: true}))
        ->Array.forEach(row =>
          switch held.contents {
          | Some(rows) => rows->Array.push(row)
          | None => write(rowHtml(row))
          }
        )
      | _ => finished := true
      | exception _ => finished := true
      }
    }
    rowsDone := true
    finishIfDone()
  }
  let pumpHtml = async () => {
    switch await decoder->Decoder.fromStream(forHtml, ~signal?) {
    | decoded =>
      let rendering = WeftDom.Html.render(
        Navigation.wrap(navigation, decoded),
        ~onError=htmlOnError,
        ~signal=?signal->Option.map(toHtmlSignal),
        ~stylesheetsOf=?stylesOf(assets)->Option.map(styles =>
          markup => stylesheetsIn(styles, markup)
        ),
      )
      switch await rendering->WeftDom.Html.shell {
      | shell =>
        writeShell(Some(shell))
        let reader = rendering->WeftDom.Html.rest->htmlStreamToStreams->Streams.getReader
        let finished = ref(false)
        while !finished.contents {
          switch await reader->Streams.Reader.read {
          | {done: false, value} =>
            if !closed.contents {
              output.contents->Option.forEach(controller => controller->Streams.enqueue(value))
            }
          | _ => finished := true
          | exception _ => finished := true
          }
        }
      // Outside every boundary: today's page, for the client to render (and to throw the error
      // again, where an error boundary can catch it).
      | exception _ => writeShell(None)
      }
    // The root row failed: the client says so.
    | exception _ => writeShell(None)
    }
    htmlDone := true
    finishIfDone()
  }
  Streams.make({
    start: controller => {
      output := Some(controller)
      write(headStart(assets, ~title, ~head=extra, ~recordEvents=true))
      pumpRows()->ignore
      pumpHtml()->ignore
    },
    cancel: _ => closed := true,
  })
}

let toStream = (element, ~assets, ~url="/", ~html=true, ~title=?, ~head=?, ~onError=?, ~signal=?) =>
  switch (html, assets.loadModule) {
  | (true, Some(loadModule)) =>
    withHtml(element, ~assets, ~loadModule, ~url, ~title, ~head, ~onError, ~signal)
  | _ => rowsOnly(element, ~assets, ~title, ~head, ~onError, ~signal)
  }

let wantsPayload = accept =>
  switch accept {
  | Some(accept) => accept->String.includes(Payload.contentType)
  | None => false
  }

external toBody: Streams.t => ReadableStream.t<Uint8Array.t> = "%identity"
external toSignal: EventTypes.abortSignal => Streams.Signal.t = "%identity"

type url = {pathname: string, search: string}
@new external parseUrl: string => url = "URL"

/** The request's path and query: what the page's URL is, on the server as in the browser. */
let pathOf = (request: Request.t) =>
  switch parseUrl(request.url) {
  | {pathname, search} => pathname ++ search
  | exception _ => "/"
  }

let respond = (request: Request.t, element, ~assets, ~html=?, ~title=?, ~head=?, ~onError=?) => {
  let signal = toSignal(request.signal)
  let (contentType, cacheControl, body) = if (
    wantsPayload(request.headers->Headers.get("accept")->Null.toOption)
  ) {
    (
      Payload.contentType,
      Payload.cacheControl,
      Render.toStream(element, ~onError?, ~signal, ~styles=?stylesOf(assets)),
    )
  } else {
    (
      "text/html; charset=utf-8",
      "no-store",
      toStream(element, ~assets, ~url=pathOf(request), ~html?, ~title?, ~head?, ~onError?, ~signal),
    )
  }
  Response.fromReadableStream(
    toBody(body),
    ~init={
      status: 200,
      headers: HeadersInit.fromDict(
        dict{"content-type": contentType, "vary": "Accept", "cache-control": cacheControl},
      ),
    },
  )
}
