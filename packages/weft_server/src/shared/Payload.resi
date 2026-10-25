/***
The payload format, shared by the server renderer (`Render`) and the client (`Client`).

A payload is a sequence of rows, each one line: `<id>:<tag><json>\n`. Row 0 is the root. The tags:

- `J`, a model: an element tree, or a value a promise resolved to.
- `E`, an entrypoint reference: `{"id": "<package>/<path>#<Module.Path>"}`. Written once per id per
  payload, before the first row that uses it.
- `C`, a stylesheet: `{"id": "<sheet id>", "href": "<its URL>"}`. Written once per sheet per payload,
  before the first row that needs it. A `J` row that needs sheets (its classes are in them) says
  which: its value is `["$C", [<C rows>], value]` (see `withSheets`).
- `X`, an error: `{"digest": ..., "message": ...}` (the message only in development builds), in place
  of a row that failed.

Inside a model, an array whose first item is the string `"$"` is an element,
`["$", type, key, props]`: `type` is a host tag, or `"$E<n>"` (the entrypoint in row n), `"$S"`
(`Suspense`) or `"$F"` (a fragment). Other strings starting with `$` are special too, and a string
that really starts with `$` is written with another in front:

| String          | Means                                              |
| --------------- | -------------------------------------------------- |
| `"$$..."`       | the string `"$..."`                                |
| `"$u"`          | `undefined`                                        |
| `"$L<n>"`       | an element that isn't ready: row n will have it    |
| `"$@<n>"`       | a promise, settled by row n                        |
| `"$NaN"`, `"$Inf"`, `"$-Inf"`, `"$-0"` | those numbers               |
| `"$n<digits>"`  | a `bigint`                                         |
| `"$D<ISO date>"`| a `Date`                                           |

JSON never puts a raw newline in its output, so a newline always ends a row.
*/

type tag =
  /** `J`: a model. */
  | Model
  /** `E`: an entrypoint reference. */
  | EntrypointRef
  /** `C`: a stylesheet. */
  | Stylesheet
  /** `X`: an error. */
  | Error

type row = {id: int, tag: tag, json: JSON.t}

/** A row as written: `<id>:<tag><json>\n`. */
let rowToString: row => string

/** Turns text, which may end in the middle of a row (or a character), back into rows. */
module Parser: {
  type t
  let make: unit => t
  /** The rows `text` completes, in order. Fails on a row that isn't one. */
  let push: (t, string) => array<row>
  /** Whether text was left over that didn't end a row: the stream ended mid-row. */
  let hasPartialRow: t => bool
}

/** What a string in a model stands for. */
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

let decodeString: string => special

/** A string as a model writes it (with another `$` in front if it starts with one). */
let string: string => JSON.t

/** A number: as itself, unless JSON can't hold it (`NaN`, the infinities, `-0`). */
let number: float => JSON.t

let undefined: JSON.t
let bigint: bigint => JSON.t
let date: Date.t => JSON.t
let lazyRow: int => JSON.t
let promiseRow: int => JSON.t
let entrypointType: int => JSON.t
let suspenseType: JSON.t
let fragmentType: JSON.t

/** `["$", type, key, props]`. */
let element: (~elementType: JSON.t, ~key: Nullable.t<string>, ~props: JSON.t) => JSON.t

/** The parts of an element, if `items` (a model's array) is one. */
let asElement: array<JSON.t> => option<(JSON.t, Nullable.t<string>, JSON.t)>

/** A `J` row's value, saying it needs the stylesheets in `rows` (`C` rows): as it is, if none. */
let withSheets: (array<int>, JSON.t) => JSON.t

/** The stylesheets a `J` row's value needs (its `C` rows), and the value itself. */
let sheetsOf: JSON.t => (array<int>, JSON.t)

/** The content type a bare payload is sent with. */
let contentType: string

/**
The `cache-control` a payload is sent with: stored by no shared cache, and never reused without the
server's say-so. Not `no-store`: Chromium keeps no body for a streamed `no-store` response, so
DevTools can't show it (it's "(canceled)", with no response to inspect).
*/
let cacheControl: string
