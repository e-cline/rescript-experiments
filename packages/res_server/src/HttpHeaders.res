/***
Reading a Web `Headers` object: an `option`-returning `get`, and iteration,
which `@rescript/webapi` doesn't bind. Header names are case-insensitive, and
iteration yields them lower-cased.
*/

type t = FetchTypes.headers

let get = (headers: t, name: string): option<string> => headers->Headers.get(name)->Null.toOption

@send external forEachRaw: (t, (string, string) => unit) => unit = "forEach"

/** Calls `f(name, value)` for each header. */
let forEach = (headers: t, f: (string, string) => unit): unit =>
  headers->forEachRaw((value, name) => f(name, value))

let toArray = (headers: t): array<(string, string)> => {
  let pairs = []
  headers->forEach((name, value) => pairs->Array.push((name, value)))
  pairs
}

/** A `Map` rather than a `dict`, because the names come from the client. */
let toMap = (headers: t): Map.t<string, string> => headers->toArray->Map.fromArray
