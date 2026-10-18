type assets = {
  scripts: array<string>,
  preloads: array<string>,
  styles: array<string>,
  entrypoints: dict<array<string>>,
}

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

let head = (assets, ~title, ~head) => {
  let tags = (urls, tag) => urls->Array.map(tag)->Array.join("")
  `<!doctype html><html lang="en"><head><meta charset="utf-8">` ++
  `<meta name="viewport" content="width=device-width, initial-scale=1">` ++
  title->Option.mapOr("", title => `<title>${escape(title)}</title>`) ++
  assets.styles->tags(url => `<link rel="stylesheet" href="${escape(url)}">`) ++
  assets.preloads->tags(url => `<link rel="modulepreload" href="${escape(url)}">`) ++
  // `async`, so the bootstrap runs once it's loaded, not once the whole page has streamed in.
  assets.scripts->tags(url => `<script type="module" async src="${escape(url)}"></script>`) ++
  head->Option.getOr("") ++ `</head><body><div id="root"></div>`
}

let tail = rowScript(None) ++ "</body></html>"

@get_index external jsonField: (JSON.t, string) => Nullable.t<JSON.t> = ""

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

let toStream = (element, ~assets, ~title=?, ~head as extra=?, ~onError=?, ~signal=?) => {
  let payload = Render.toStream(element, ~onError?, ~signal?)
  let reader = payload->Streams.getReader
  let decoder = Streams.Decoder.make()
  let encoder = Streams.Encoder.make()
  let parser = Payload.Parser.make()
  let preloaded = Set.make()
  let html = (row: Payload.row) => {
    let preload = switch entrypointFile(row) {
    | Some(file) if !(preloaded->Set.has(file)) =>
      preloaded->Set.add(file)
      assets.entrypoints
      ->Dict.get(file)
      ->Option.getOr([])
      ->Array.map(url => `<link rel="modulepreload" href="${escape(url)}">`)
      ->Array.join("")
    | _ => ""
    }
    preload ++ rowScript(Some(Payload.rowToString(row)))
  }
  Streams.make({
    start: controller =>
      controller->Streams.enqueue(
        encoder->Streams.Encoder.encode(head(assets, ~title, ~head=extra)),
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

let wantsPayload = accept =>
  switch accept {
  | Some(accept) => accept->String.includes(Payload.contentType)
  | None => false
  }

external toBody: Streams.t => ReadableStream.t<Uint8Array.t> = "%identity"
external toSignal: EventTypes.abortSignal => Streams.Signal.t = "%identity"

let respond = (request: Request.t, element, ~assets, ~title=?, ~head=?, ~onError=?) => {
  let signal = toSignal(request.signal)
  let (contentType, body) = if wantsPayload(request.headers->Headers.get("accept")->Null.toOption) {
    (Payload.contentType, Render.toStream(element, ~onError?, ~signal))
  } else {
    ("text/html; charset=utf-8", toStream(element, ~assets, ~title?, ~head?, ~onError?, ~signal))
  }
  Response.fromReadableStream(
    toBody(body),
    ~init={
      status: 200,
      headers: HeadersInit.fromDict(
        dict{"content-type": contentType, "vary": "Accept", "cache-control": "no-store"},
      ),
    },
  )
}
