type tag =
  | Model
  | EntrypointRef
  | Stylesheet
  | Error

type row = {id: int, tag: tag, json: JSON.t}

let tagLetter = tag =>
  switch tag {
  | Model => "J"
  | EntrypointRef => "E"
  | Stylesheet => "C"
  | Error => "X"
  }

let rowToString = row =>
  `${Int.toString(row.id)}:${tagLetter(row.tag)}${JSON.stringify(row.json)}\n`

let fail = text =>
  Errors.fail(
    1,
    Common.Env.isDev
      ? `WeftServer: a payload row isn't one: ${text->String.slice(~start=0, ~end=80)}`
      : "",
  )

let parseRow = (line: string): row => {
  let colon = line->String.indexOf(":")
  let id = colon > 0 ? Int.fromString(line->String.slice(~start=0, ~end=colon)) : None
  let tag = switch line->String.charAt(colon + 1) {
  | "J" => Some(Model)
  | "E" => Some(EntrypointRef)
  | "C" => Some(Stylesheet)
  | "X" => Some(Error)
  | _ => None
  }
  switch (id, tag) {
  | (Some(id), Some(tag)) =>
    switch JSON.parseOrThrow(line->String.slice(~start=colon + 2)) {
    | json => {id, tag, json}
    | exception _ => fail(line)
    }
  | _ => fail(line)
  }
}

module Parser = {
  type t = {mutable rest: string}
  let make = () => {rest: ""}
  let push = (parser, text) => {
    let lines = (parser.rest ++ text)->String.split("\n")

    // The last piece is whatever follows the last newline: the start of a row, or "".
    parser.rest = lines->Array.pop->Option.getOr("")
    lines->Array.map(parseRow)
  }
  let hasPartialRow = parser => parser.rest != ""
}

type special =
  | Literal(string)
  | Undefined
  | LazyRow(int)
  | PromiseRow(int)
  | EntrypointType(int)
  | SuspenseType
  | FragmentType
  | Number(float)
  | BigInt(bigint)
  | Date(Date.t)

let rowOf = (text, ~prefix) => Int.fromString(text->String.slice(~start=String.length(prefix)))

let decodeString = text =>
  if !(text->String.startsWith("$")) {
    Literal(text)
  } else {
    switch text {
    | "$u" => Undefined
    | "$S" => SuspenseType
    | "$F" => FragmentType
    | "$NaN" => Number(Float.Constants.nan)
    | "$Inf" => Number(Float.Constants.positiveInfinity)
    | "$-Inf" => Number(Float.Constants.negativeInfinity)
    | "$-0" => Number(-0.0)
    | _ =>
      let with_ = (prefix, make) =>
        switch rowOf(text, ~prefix) {
        | Some(id) => make(id)
        | None => fail(text)
        }
      if text->String.startsWith("$$") {
        Literal(text->String.slice(~start=1))
      } else if text->String.startsWith("$L") {
        with_("$L", id => LazyRow(id))
      } else if text->String.startsWith("$@") {
        with_("$@", id => PromiseRow(id))
      } else if text->String.startsWith("$E") {
        with_("$E", id => EntrypointType(id))
      } else if text->String.startsWith("$n") {
        switch BigInt.fromStringOrThrow(text->String.slice(~start=2)) {
        | value => BigInt(value)
        | exception _ => fail(text)
        }
      } else if text->String.startsWith("$D") {
        Date(Date.fromString(text->String.slice(~start=2)))
      } else {
        fail(text)
      }
    }
  }

let string = text => JSON.Encode.string(text->String.startsWith("$") ? "$" ++ text : text)

let isNegativeZero = (x: float) => x == 0.0 && 1.0 /. x < 0.0

let number = x =>
  if Float.isNaN(x) {
    JSON.Encode.string("$NaN")
  } else if x == Float.Constants.positiveInfinity {
    JSON.Encode.string("$Inf")
  } else if x == Float.Constants.negativeInfinity {
    JSON.Encode.string("$-Inf")
  } else if isNegativeZero(x) {
    JSON.Encode.string("$-0")
  } else {
    JSON.Encode.float(x)
  }

let undefined = JSON.Encode.string("$u")
let bigint = value => JSON.Encode.string("$n" ++ BigInt.toString(value))
let date = value => JSON.Encode.string("$D" ++ Date.toISOString(value))
let lazyRow = id => JSON.Encode.string("$L" ++ Int.toString(id))
let promiseRow = id => JSON.Encode.string("$@" ++ Int.toString(id))
let entrypointType = id => JSON.Encode.string("$E" ++ Int.toString(id))
let suspenseType = JSON.Encode.string("$S")
let fragmentType = JSON.Encode.string("$F")

let element = (~elementType, ~key, ~props) =>
  JSON.Encode.array([
    JSON.Encode.string("$"),
    elementType,
    switch Nullable.toOption(key) {
    | Some(key) => JSON.Encode.string(key)
    | None => JSON.Encode.null
    },
    props,
  ])

let asElement = items =>
  switch items {
  | [JSON.String("$"), elementType, key, props] =>
    let key = switch key {
    | JSON.String(key) => Nullable.make(key)
    | _ => Nullable.null
    }
    Some((elementType, key, props))
  | _ => None
  }

let withSheets = (rows, json) =>
  Array.length(rows) == 0
    ? json
    : JSON.Encode.array([
        JSON.String("$C"),
        JSON.Encode.array(rows->Array.map(row => JSON.Encode.int(row))),
        json,
      ])

let sheetsOf = json =>
  switch json {
  | JSON.Array([JSON.String("$C"), JSON.Array(rows), inner]) => (
      rows->Array.filterMap(row => row->JSON.Decode.float->Option.map(Float.toInt)),
      inner,
    )
  | _ => ([], json)
  }

let contentType = "text/x-weft-payload"

let cacheControl = "private, no-cache"
