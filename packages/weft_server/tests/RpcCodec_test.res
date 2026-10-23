/***
`Rpc.Codec`: every combinator round-trips random values (through `JSON.stringify` and
`JSON.parse`, as a request does), and reading refuses what doesn't fit, saying where, while
ignoring what it doesn't know, and changing no prototype whatever the names in a request are.
*/

open Vitest

module Codec = Rpc.Codec

/** A seeded Lehmer PRNG (as in `Fuzz_test`), so failures reproduce. */
module Random = {
  type t = ref<float>
  let make = (seed: float): t => ref(seed)
  let next = (state: t): float => {
    let product = state.contents *. 48271.0
    state := product -. 2147483647.0 *. Math.floor(product /. 2147483647.0)
    state.contents
  }
  let intBelow = (state: t, bound: int): int => mod(Float.toInt(next(state)), bound)
  let pick = (state: t, items: array<'a>): 'a =>
    items->Array.getUnsafe(intBelow(state, Array.length(items)))
  let bool = state => intBelow(state, 2) == 0
}

type shape = Circle(float) | Square({side: float}) | Dot

type item = {
  name: string,
  count: int,
  price: float,
  tags: array<string>,
  note: option<string>,
  scores: dict<int>,
  at: Date.t,
  shape: shape,
}

let shape = Codec.variant(
  [
    Codec.case("Circle", Codec.float, radius => Circle(radius)),
    Codec.case(
      "Square",
      Codec.object1(("side", Codec.float), side => side, side => side),
      side => Square({side: side}),
    ),
    Codec.constant("Dot", Dot),
  ],
  ~encode=shape =>
    switch shape {
    | Circle(radius) => Codec.tagged("Circle", Codec.float, radius)
    | Square({side}) =>
      Codec.tagged("Square", Codec.object1(("side", Codec.float), side => side, side => side), side)
    | Dot => Codec.tag("Dot")
    },
)

let item = Codec.object8(
  ("name", Codec.string),
  ("count", Codec.int),
  ("price", Codec.float),
  ("tags", Codec.array(Codec.string)),
  ("note", Codec.option(Codec.string)),
  ("scores", Codec.dict(Codec.int)),
  ("at", Codec.date),
  ("shape", shape),
  (name, count, price, tags, note, scores, at, shape) => {
    name,
    count,
    price,
    tags,
    note,
    scores,
    at,
    shape,
  },
  ({name, count, price, tags, note, scores, at, shape}) => (
    name,
    count,
    price,
    tags,
    note,
    scores,
    at,
    shape,
  ),
)

/** Strings of every awkward kind: empty, quotes, non-ASCII, line separators, prototype names. */
let strings = [
  "",
  "plain",
  "with \"quotes\" and \\ backslashes",
  "new\nline",
  "é ü 漢字 🎉",
  "  ",
  "__proto__",
  "constructor",
  "</script>",
]

let randomString = random =>
  Random.bool(random)
    ? Random.pick(random, strings)
    : Int.toString(Random.intBelow(random, 100000)) ++ Random.pick(random, strings)

let randomInt = random =>
  switch Random.intBelow(random, 4) {
  | 0 => 2147483647
  | 1 => -2147483648
  | 2 => 0
  | _ => Random.intBelow(random, 2000000) - 1000000
  }

let randomFloat = random =>
  switch Random.intBelow(random, 3) {
  | 0 => 0.
  | 1 => Random.next(random) /. 7.
  | _ => -.Random.next(random) *. 1e10
  }

let randomItem = random => {
  name: randomString(random),
  count: randomInt(random),
  price: randomFloat(random),
  tags: Array.fromInitializer(~length=Random.intBelow(random, 4), _ => randomString(random)),
  note: Random.bool(random) ? Some(randomString(random)) : None,
  scores: Dict.fromArray(
    Array.fromInitializer(~length=Random.intBelow(random, 4), _ => (
      randomString(random),
      randomInt(random),
    )),
  ),
  at: Date.fromTime(Math.floor(Random.next(random) *. 1000.)),
  shape: switch Random.intBelow(random, 3) {
  | 0 => Circle(randomFloat(random))
  | 1 => Square({side: randomFloat(random)})
  | _ => Dot
  },
}

/** `value` written, sent as a request's text, and read back. */
let roundTrip = (codec, value) =>
  Codec.decode(codec, JSON.parseOrThrow(JSON.stringify(Codec.encode(codec, value))))

let decodeText = (codec, text) => Codec.decode(codec, JSON.parseOrThrow(text))

@scope("Object") @val external prototypeOf: 'a => Nullable.t<unknown> = "getPrototypeOf"
let objectPrototype: unknown = %raw(`Object.prototype`)
@scope("Object") @val external ownKeys: 'a => array<string> = "keys"
let polluted: unit => bool = %raw(`() => ({}).polluted !== undefined`)

describe("round trips", () => {
  test("each combinator, over random values", t => {
    for seed in 1 to 300 {
      let random = Random.make(Int.toFloat(seed))
      let value = randomItem(random)
      t->expect(roundTrip(item, value))->Expect.toEqual(Ok(value))
    }
  })

  test("arrays of objects, and options of arrays", t => {
    let random = Random.make(7.)
    let items = Array.fromInitializer(~length=20, _ => randomItem(random))
    t->expect(roundTrip(Codec.array(item), items))->Expect.toEqual(Ok(items))
    t
    ->expect(roundTrip(Codec.option(Codec.array(Codec.int)), Some([1, 2])))
    ->Expect.toEqual(Ok(Some([1, 2])))
    t->expect(roundTrip(Codec.option(Codec.array(Codec.int)), None))->Expect.toEqual(Ok(None))
  })

  test("map and custom", t => {
    let even =
      Codec.int->Codec.map(
        ~decode=n => mod(n, 2) == 0 ? Ok(n / 2) : Error("expected an even number"),
        ~encode=half => half * 2,
      )
    t->expect(roundTrip(even, 21))->Expect.toEqual(Ok(21))
    t->expect(decodeText(even, "3"))->Expect.toEqual(Error("the request: expected an even number"))
    let upper = Codec.custom(
      ~encode=text => JSON.Encode.string(String.toUpperCase(text)),
      ~decode=json =>
        switch json {
        | String(text) => Ok(String.toLowerCase(text))
        | _ => Error("expected text")
        },
    )
    t->expect(roundTrip(upper, "abc"))->Expect.toEqual(Ok("abc"))
    t
    ->expect(decodeText(Codec.array(upper), `["A", 1]`))
    ->Expect.toEqual(Error("[1]: expected text"))
  })

  test("a date, as toISOString writes it", t => {
    let date = Date.fromString("2026-10-18T12:34:56.789Z")
    t
    ->expect(Codec.encode(Codec.date, date))
    ->Expect.toEqual(JSON.String("2026-10-18T12:34:56.789Z"))
    t->expect(roundTrip(Codec.date, date))->Expect.toEqual(Ok(date))
  })
})

describe("reading refuses", () => {
  test("a value of the wrong type, saying where", t => {
    t
    ->expect(decodeText(Codec.string, "1"))
    ->Expect.toEqual(Error("the request: expected a string, got a number"))
    t
    ->expect(decodeText(Codec.array(Codec.bool), "[true, null]"))
    ->Expect.toEqual(Error("[1]: expected a boolean, got null"))
    t
    ->expect(decodeText(Codec.dict(Codec.array(Codec.int)), `{"a": [1, "2"]}`))
    ->Expect.toEqual(Error(".a[1]: expected a whole number, got a string"))
    t
    ->expect(
      decodeText(
        Codec.object1(("tags", Codec.array(Codec.string)), x => x, x => x),
        `{"tags": {}}`,
      ),
    )
    ->Expect.toEqual(Error(".tags: expected an array, got an object"))
  })

  test("a field that's missing, unless it's an option", t => {
    let codec = Codec.object2(
      ("name", Codec.string),
      ("note", Codec.option(Codec.string)),
      (name, note) => (name, note),
      pair => pair,
    )
    t->expect(decodeText(codec, `{}`))->Expect.toEqual(Error(".name: missing"))
    t->expect(decodeText(codec, `{"name": "a"}`))->Expect.toEqual(Ok(("a", None)))
    t->expect(decodeText(codec, `{"name": "a", "note": null}`))->Expect.toEqual(Ok(("a", None)))
    t
    ->expect(decodeText(codec, `{"name": "a", "note": 1}`))
    ->Expect.toEqual(Error(".note: expected a string, got a number"))
  })

  test("numbers out of range", t => {
    t
    ->expect(decodeText(Codec.int, "2147483648"))
    ->Expect.toEqual(Error("the request: expected a whole number that fits in an int"))
    t
    ->expect(decodeText(Codec.int, "1.5"))
    ->Expect.toEqual(Error("the request: expected a whole number that fits in an int"))
    t->expect(decodeText(Codec.int, "1e3"))->Expect.toEqual(Ok(1000))
    // `JSON.parse` never gives these, but a `custom` codec's caller could pass them on.
    t
    ->expect(Codec.decode(Codec.float, JSON.Encode.float(Float.Constants.positiveInfinity)))
    ->Expect.toEqual(Error("the request: expected a finite number"))
  })

  test("dates other than toISOString's", t => {
    t
    ->expect(decodeText(Codec.date, `"2026-10-18"`))
    ->Expect.toEqual(
      Error("the request: expected a date (an ISO 8601 string, as toISOString writes)"),
    )
    t
    ->expect(decodeText(Codec.date, `"tomorrow"`))
    ->Expect.toEqual(
      Error("the request: expected a date (an ISO 8601 string, as toISOString writes)"),
    )
  })

  test("a variant's unknown tag, or a missing payload", t => {
    t
    ->expect(decodeText(shape, `{"tag": "Triangle"}`))
    ->Expect.toEqual(Error(`.tag: expected one of "Circle", "Square", "Dot"`))
    t->expect(decodeText(shape, `{"tag": "Circle"}`))->Expect.toEqual(Error(".value: missing"))
    t->expect(decodeText(shape, `{"value": 1}`))->Expect.toEqual(Error(".tag: missing"))
    t
    ->expect(decodeText(shape, `"Dot"`))
    ->Expect.toEqual(Error("the request: expected an object, got a string"))
    // Names a prototype has aren't tags.
    ["constructor", "toString", "__proto__", "hasOwnProperty"]->Array.forEach(
      name =>
        t
        ->expect(decodeText(shape, `{"tag": "${name}"}`)->Result.isError)
        ->Expect.toBe(true),
    )
  })
})

describe("what reading ignores", () => {
  test("fields the codec doesn't know", t => {
    let codec = Codec.object1(
      ("name", Codec.string),
      name => {"name": name},
      value => value["name"],
    )
    switch decodeText(codec, `{"name": "a", "isAdmin": true, "extra": {"deep": [1]}}`) {
    | Ok(value) => t->expect(ownKeys(value))->Expect.toEqual(["name"])
    | Error(message) => JsError.throwWithMessage(message)
    }
  })

  test("prototype names, as fields, in dicts and in objects", t => {
    let text = `{"__proto__": {"polluted": 1}, "constructor": {"prototype": {"polluted": 1}}, "name": "a"}`
    // An object codec reads only its own fields, and builds the value itself.
    let codec = Codec.object1(
      ("name", Codec.string),
      name => {"name": name},
      value => value["name"],
    )
    switch decodeText(codec, text) {
    | Ok(value) =>
      t->expect(prototypeOf(value)->Nullable.toOption)->Expect.toEqual(Some(objectPrototype))
    | Error(message) => JsError.throwWithMessage(message)
    }
    // A dict keeps them, as its own entries, without changing its prototype.
    let dict = Codec.dict(Codec.custom(~encode=json => json, ~decode=json => Ok(json)))
    switch decodeText(dict, text) {
    | Ok(value) =>
      t->expect(prototypeOf(value)->Nullable.toOption)->Expect.toEqual(Some(objectPrototype))
      t->expect(ownKeys(value))->Expect.toEqual(["__proto__", "constructor", "name"])
      t->expect(roundTrip(dict, value))->Expect.toEqual(Ok(value))
    | Error(message) => JsError.throwWithMessage(message)
    }
    t->expect(polluted())->Expect.toBe(false)
  })

  test("inherited properties: a field named after one is missing, not found", t => {
    let codec = Codec.object1(("constructor", Codec.string), name => name, name => name)
    t->expect(decodeText(codec, `{}`))->Expect.toEqual(Error(".constructor: missing"))
    t->expect(decodeText(codec, `{"constructor": "own"}`))->Expect.toEqual(Ok("own"))
    let toString = Codec.object1(
      ("toString", Codec.option(Codec.string)),
      name => name,
      name => name,
    )
    t->expect(decodeText(toString, `{}`))->Expect.toEqual(Ok(None))
  })
})
