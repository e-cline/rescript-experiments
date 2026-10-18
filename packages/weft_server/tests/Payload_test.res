/***
The payload format on its own: what strings, numbers and references encode to and decode from,
and rows surviving being cut anywhere on the way.
*/

open Vitest

let roundTrip = (json: JSON.t): Payload.special =>
  switch json {
  | String(text) => Payload.decodeString(text)
  | Number(value) => Number(value)
  | _ => JsError.throwWithMessage("not a string or number")
  }

let sameNumber = (a: float, b: float) => Object.is(a, b)

describe("Payload: values", () => {
  test("strings round-trip, including ones that start with $", t => {
    [
      "plain",
      "",
      "$",
      "$$",
      "$u",
      "$L5",
      "$$$x",
      "snow ☃ and 𝄞",
      "line\nbreak",
    ]->Array.forEach(
      text => t->expect(roundTrip(Payload.string(text)))->Expect.toEqual(Literal(text)),
    )
  })

  test("numbers round-trip, including the ones JSON can't hold", t => {
    [
      0.0,
      1.5,
      -2.0,
      1e300,
      Float.Constants.nan,
      Float.Constants.positiveInfinity,
      Float.Constants.negativeInfinity,
      -0.0,
    ]->Array.forEach(
      value =>
        switch roundTrip(Payload.number(value)) {
        | Number(decoded) => t->expect(sameNumber(decoded, value))->Expect.toBe(true)
        | _ => t->expect("a number")->Expect.toBe("something else")
        },
    )
  })

  test("undefined, bigints and dates round-trip", t => {
    t->expect(roundTrip(Payload.undefined))->Expect.toEqual(Undefined)
    t
    ->expect(roundTrip(Payload.bigint(12345678901234567890n)))
    ->Expect.toEqual(BigInt(12345678901234567890n))
    let date = Date.fromString("2026-10-18T12:34:56.789Z")
    switch roundTrip(Payload.date(date)) {
    | Date(decoded) => t->expect(Date.getTime(decoded))->Expect.toBe(Date.getTime(date))
    | _ => t->expect("a date")->Expect.toBe("something else")
    }
  })

  test("references and element types round-trip", t => {
    t->expect(roundTrip(Payload.lazyRow(5)))->Expect.toEqual(LazyRow(5))
    t->expect(roundTrip(Payload.promiseRow(12)))->Expect.toEqual(PromiseRow(12))
    t->expect(roundTrip(Payload.entrypointType(3)))->Expect.toEqual(EntrypointType(3))
    t->expect(roundTrip(Payload.suspenseType))->Expect.toEqual(SuspenseType)
    t->expect(roundTrip(Payload.fragmentType))->Expect.toEqual(FragmentType)
  })

  test("an element is an array starting with \"$\", and a list isn't", t => {
    let element = Payload.element(
      ~elementType=Payload.string("div"),
      ~key=Nullable.make("k"),
      ~props=JSON.Encode.object(dict{}),
    )
    t->expect(JSON.stringify(element))->Expect.toBe(`["$","div","k",{}]`)
    switch element {
    | Array(items) => t->expect(Payload.asElement(items)->Option.isSome)->Expect.toBe(true)
    | _ => ()
    }
    // A list whose first item is the text "$": the text is written "$$", so it isn't taken for one.
    let list = [
      Payload.string("$"),
      Payload.string("div"),
      JSON.Encode.null,
      JSON.Encode.object(dict{}),
    ]
    t->expect(Payload.asElement(list)->Option.isSome)->Expect.toBe(false)
  })

  test("strings that look special but aren't fail clearly", t => {
    ["$x", "$Lnope", "$nnot-a-number"]->Array.forEach(
      text => t->expect(() => Payload.decodeString(text))->Expect.toThrow,
    )
  })
})

let encoder = Streams.Encoder.make()
@send external subarray: (Uint8Array.t, int, int) => Uint8Array.t = "subarray"
@get external byteLength: Uint8Array.t => int = "length"

/** Parses `pieces` of a payload's bytes as the client does: decoding each, then parsing. */
let parseBytes = (pieces: array<Uint8Array.t>) => {
  let decoder = Streams.Decoder.make()
  let parser = Payload.Parser.make()
  let rows =
    pieces->Array.flatMap(piece =>
      parser->Payload.Parser.push(decoder->Streams.Decoder.decode(piece, {stream: true}))
    )
  (rows->Array.map(Payload.rowToString), Payload.Parser.hasPartialRow(parser))
}

describe("Payload: rows", () => {
  let sample: array<Payload.row> = [
    {
      id: 1,
      tag: EntrypointRef,
      json: JSON.Encode.object(dict{"id": JSON.Encode.string("pkg/src/A.res#")}),
    },
    {
      id: 0,
      tag: Model,
      json: JSON.parseOrThrow(`["$","p",null,{"children":["snow ☃", "$L2", "𝄞"]}]`),
    },
    {id: 2, tag: Error, json: JSON.parseOrThrow(`{"message":"it broke\\non two lines"}`)},
  ]
  let text = sample->Array.map(Payload.rowToString)->Array.join("")

  test("are one line each: <id>:<tag><json>", t => {
    t
    ->expect(text->String.split("\n")->Array.filter(line => line != ""))
    ->Expect.toEqual([
      `1:E{"id":"pkg/src/A.res#"}`,
      `0:J["$","p",null,{"children":["snow ☃","$L2","𝄞"]}]`,
      `2:X{"message":"it broke\\non two lines"}`,
    ])
  })

  test("parse back the same, however the bytes are cut in two (inside a character too)", t => {
    let bytes = encoder->Streams.Encoder.encode(text)
    let length = byteLength(bytes)
    let expected = sample->Array.map(Payload.rowToString)
    for cut in 0 to length {
      let (rows, partial) = parseBytes([bytes->subarray(0, cut), bytes->subarray(cut, length)])
      t->expect((cut, rows, partial))->Expect.toEqual((cut, expected, false))
    }
  })

  test("parse back the same when cut into pieces of every size", t => {
    let bytes = encoder->Streams.Encoder.encode(text)
    let length = byteLength(bytes)
    for size in 1 to 17 {
      let pieces = Array.fromInitializer(
        ~length=(length + size - 1) / size,
        index => bytes->subarray(index * size, Math.Int.min((index + 1) * size, length)),
      )
      t
      ->expect((size, parseBytes(pieces)))
      ->Expect.toEqual((size, (sample->Array.map(Payload.rowToString), false)))
    }
  })

  test("a row cut off at the end is reported as partial", t => {
    let parser = Payload.Parser.make()
    t->expect(parser->Payload.Parser.push(`0:J"whole"\n1:J"ha`)->Array.length)->Expect.toBe(1)
    t->expect(Payload.Parser.hasPartialRow(parser))->Expect.toBe(true)
  })

  test("a line that isn't a row fails clearly", t => {
    [`x:J1\n`, `1:Q{}\n`, `1:J{\n`, `J1\n`]->Array.forEach(
      line => t->expect(() => Payload.Parser.make()->Payload.Parser.push(line))->Expect.toThrow,
    )
  })
})
