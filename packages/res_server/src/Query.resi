/***
Read-only access to query parameters (or any other URL-encoded key/value
data, such as a submitted form): a wrapper over the Web `URLSearchParams`
whose getters return `option`s instead of `null`, and which can parse values
as numbers and booleans.

A name can appear more than once (`?tag=a&tag=b`). The single-value getters
use its first value; `getAll` returns all of them.
*/

type t

let fromSearchParams: URLSearchParams.t => t

/** Parses a query string, with or without its leading `?`. */
let fromString: string => t

let fromPairs: array<(string, string)> => t

/** The underlying `URLSearchParams`. Don't mutate it. */
let toSearchParams: t => URLSearchParams.t

let has: (t, string) => bool

/** The first value for `name`, if there is one. */
let get: (t, string) => option<string>

/** Every value for `name`, in order; empty if there are none. */
let getAll: (t, string) => array<string>

let getOr: (t, string, string) => string

/**
The first value for `name` as an integer: an optional sign and decimal digits,
nothing else. `None` if it's missing, isn't one (`"1.5"`, `"12px"`, `""`), or
doesn't fit in an `int`.
*/
let getInt: (t, string) => option<int>

/**
The first value for `name` as a finite decimal number (`"1.5"`, `"-2"`,
`"1e3"`). `None` if it's missing or isn't one.
*/
let getFloat: (t, string) => option<float>

/**
The first value for `name` as a boolean: `true`, `1`, or no value at all (a
bare `?flag`) are `true`; `false` and `0` are `false`. `None` if it's missing
or anything else.
*/
let getBool: (t, string) => option<bool>

let isEmpty: t => bool

/** Every name/value pair, in order, including repeated names. */
let toArray: t => array<(string, string)>

/**
Each name with its first value. A `Map` rather than a `dict`, because the
names come from the client: looking up `"constructor"` in a `dict` finds
something whether or not it was sent.
*/
let toMap: t => Map.t<string, string>

/** The URL-encoded form, without a leading `?`. */
let toString: t => string
