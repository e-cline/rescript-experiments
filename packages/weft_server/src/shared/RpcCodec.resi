/***
How an RPC's request goes over the wire (`Rpc.Codec`): each codec writes a value as plain JSON on
the client, and reads it back on the server, checking it as it goes.

```rescript
type addComment = {noteId: string, author: string, text: string}

let addComment = Codec.object3(
  ("noteId", Codec.string),
  ("author", Codec.string),
  ("text", Codec.string),
  (noteId, author, text) => {noteId, author, text},
  ({noteId, author, text}) => (noteId, author, text),
)
```

A request comes from anyone, so reading one is strict where it matters and ignores the rest:

- Every value is checked against its codec (a string is a string, an `int` a whole number in
  range), and the first thing that doesn't fit fails the whole request, with where it is (`.text`,
  `.tags[2]`) and what was wrong.
- Fields are read as the object's own properties, by the names the codec knows: one the sender
  added is ignored, and `__proto__`, `constructor` and the like are just names. Objects are built
  afresh by the codec's own function, and dicts as new objects, so nothing in a request changes a
  prototype.
- Nothing in a request chooses what code runs: there are no references, tags that load anything, or
  classes. Reading one takes time in proportion to its size.
*/

/** A codec for values of type `'a`. */
type t<'a>

/** Writes `value` as JSON. */
let encode: (t<'a>, 'a) => JSON.t

/**
Reads a value from JSON (what `JSON.parse` gave), or says where and why it doesn't fit:
`".text: expected a string, got a number"`.
*/
let decode: (t<'a>, JSON.t) => result<'a, string>

/** A string. */
let string: t<string>

/** A whole number that fits in an `int` (32 bits, signed). */
let int: t<int>

/** A finite number. */
let float: t<float>

let bool: t<bool>

/**
`None` as `null`, and `Some(value)` as `value`. A field that's an option can also be left out, and
reads as `None`. An option of an option can't tell `Some(None)` from `None`: both are `null`.
*/
let option: t<'a> => t<option<'a>>

let array: t<'a> => t<array<'a>>

/** A dict, as an object. */
let dict: t<'a> => t<dict<'a>>

/** A date, as an ISO 8601 string (`Date.toISOString`'s). */
let date: t<Date.t>

/**
A codec for `'b` written as an `'a`: `decode` turns what `codec` read into a `'b` (or says why it
can't, a message), and `encode` turns a `'b` into what `codec` writes.

```rescript
let email = Codec.string->Codec.map(
  ~decode=text => text->String.includes("@") ? Ok(text) : Error("expected an email address"),
  ~encode=text => text,
)
```
*/
let map: (t<'a>, ~decode: 'a => result<'b, string>, ~encode: 'b => 'a) => t<'b>

/** A codec of your own, over the JSON itself. `decode`'s errors are messages. */
let custom: (~encode: 'a => JSON.t, ~decode: JSON.t => result<'a, string>) => t<'a>

/** A field of an object: its name, and its value's codec. */
type field<'a> = (string, t<'a>)

/**
An object with these fields, read into a value with `make`, and written from one with `unmake`
(usually a record's fields, as a tuple). The rest of `object1` to `object8` are the same, with more
fields.
*/
let object1: (field<'a>, 'a => 'value, 'value => 'a) => t<'value>
let object2: (field<'a>, field<'b>, ('a, 'b) => 'value, 'value => ('a, 'b)) => t<'value>
let object3: (
  field<'a>,
  field<'b>,
  field<'c>,
  ('a, 'b, 'c) => 'value,
  'value => ('a, 'b, 'c),
) => t<'value>
let object4: (
  field<'a>,
  field<'b>,
  field<'c>,
  field<'d>,
  ('a, 'b, 'c, 'd) => 'value,
  'value => ('a, 'b, 'c, 'd),
) => t<'value>
let object5: (
  field<'a>,
  field<'b>,
  field<'c>,
  field<'d>,
  field<'e>,
  ('a, 'b, 'c, 'd, 'e) => 'value,
  'value => ('a, 'b, 'c, 'd, 'e),
) => t<'value>
let object6: (
  field<'a>,
  field<'b>,
  field<'c>,
  field<'d>,
  field<'e>,
  field<'f>,
  ('a, 'b, 'c, 'd, 'e, 'f) => 'value,
  'value => ('a, 'b, 'c, 'd, 'e, 'f),
) => t<'value>
let object7: (
  field<'a>,
  field<'b>,
  field<'c>,
  field<'d>,
  field<'e>,
  field<'f>,
  field<'g>,
  ('a, 'b, 'c, 'd, 'e, 'f, 'g) => 'value,
  'value => ('a, 'b, 'c, 'd, 'e, 'f, 'g),
) => t<'value>
let object8: (
  field<'a>,
  field<'b>,
  field<'c>,
  field<'d>,
  field<'e>,
  field<'f>,
  field<'g>,
  field<'h>,
  ('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h) => 'value,
  'value => ('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h),
) => t<'value>

/** One case of a variant, for reading it: its tag, and how to make the variant from it. */
type case<'a>

/** A case with a payload, read with `codec` and made into the variant with `make`. */
let case: (string, t<'payload>, 'payload => 'a) => case<'a>

/** A case without one. */
let constant: (string, 'a) => case<'a>

/** Which case a value is, for writing it: from `tagged` or `tag`. */
type tagged

/** A case with a payload: its tag, the payload's codec, and the payload. */
let tagged: (string, t<'payload>, 'payload) => tagged

/** A case without one. */
let tag: string => tagged

/**
A variant, from its cases: written as `{"tag": "Circle", "value": 1.5}` (or `{"tag": "Dot"}`), read
by looking its tag up in `cases`. `encode` says which case a value is (a `switch`, so the compiler
checks every case is there).

```rescript
type shape = Circle(float) | Dot

let shape = Codec.variant(
  [Codec.case("Circle", Codec.float, radius => Circle(radius)), Codec.constant("Dot", Dot)],
  ~encode=shape =>
    switch shape {
    | Circle(radius) => Codec.tagged("Circle", Codec.float, radius)
    | Dot => Codec.tag("Dot")
    },
)
```
*/
let variant: (array<case<'a>>, ~encode: 'a => tagged) => t<'a>
