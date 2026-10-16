type t = URLSearchParams.t

let fromSearchParams = (params: URLSearchParams.t): t => params

let fromString = (query: string): t => URLSearchParams.fromString(query)

let fromPairs = (pairs: array<(string, string)>): t => URLSearchParams.fromKeyValueArray(pairs)

let toSearchParams = (query: t): URLSearchParams.t => query

let has = (query: t, name: string): bool => query->URLSearchParams.has(~name)

let get = (query: t, name: string): option<string> =>
  query->URLSearchParams.get(name)->Null.toOption

let getAll = (query: t, name: string): array<string> => query->URLSearchParams.getAll(name)

let getOr = (query: t, name: string, default: string): string =>
  query->get(name)->Option.getOr(default)

// Stricter than `Float.fromString`, which accepts anything starting with a
// number ("12px" is 12).
let parseFloat = (value: string): option<float> =>
  if /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/->RegExp.test(value) {
    value->Float.fromString->Option.filter(Float.isFinite)
  } else {
    None
  }

let getFloat = (query: t, name: string): option<float> =>
  query->get(name)->Option.flatMap(parseFloat)

let getInt = (query: t, name: string): option<int> =>
  switch query->get(name) {
  | Some(value) if /^[+-]?\d+$/->RegExp.test(value) =>
    // Out of `int`'s range if it doesn't survive the round trip.
    value
    ->Float.fromString
    ->Option.filter(float => Float.toInt(float)->Int.toFloat == float)
    ->Option.map(Float.toInt)
  | _ => None
  }

let getBool = (query: t, name: string): option<bool> =>
  switch query->get(name)->Option.map(String.toLowerCase) {
  | Some("true" | "1" | "") => Some(true)
  | Some("false" | "0") => Some(false)
  | Some(_) | None => None
  }

let toArray = (query: t): array<(string, string)> =>
  query->URLSearchParams.entries->Iterator.toArray

let isEmpty = (query: t): bool => query->toArray->Array.length == 0

let toMap = (query: t): Map.t<string, string> => {
  let map = Map.make()
  query
  ->toArray
  ->Array.forEach(((name, value)) =>
    if !(map->Map.has(name)) {
      map->Map.set(name, value)
    }
  )
  map
}

let toString = (query: t): string => URLSearchParams.toString(query)
