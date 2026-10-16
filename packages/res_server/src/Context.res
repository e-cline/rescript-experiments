module Key = {
  // The type parameter is a phantom: it records the type of the values stored
  // under the key, which is what makes the casts below sound. A key is found
  // by its identity, so each call to `make` is a different key whatever its
  // name, including across separately loaded copies of this module.
  type t<'a> = {name: string}

  let make = (~name: string): t<'a> => {name: name}

  let name = (key: t<'a>): string => key.name
}

// A key with its type parameter forgotten, to hold keys of every type in one map.
type anyKey

external toAnyKey: Key.t<'a> => anyKey = "%identity"

// Each value is stored in a box, so that a key whose value is itself `None`
// reads back as `Some(None)` rather than as missing.
type box = {value: unknown}

type t = Map.t<anyKey, box>

external toUnknown: 'a => unknown = "%identity"

// Only ever applied to a value that `set` stored under the same key, and so
// with the same `'a`.
external fromUnknown: unknown => 'a = "%identity"

let empty: t = Map.make()

let get = (context: t, key: Key.t<'a>): option<'a> =>
  context->Map.get(toAnyKey(key))->Option.map(box => fromUnknown(box.value))

let set = (context: t, key: Key.t<'a>, value: 'a): t => {
  let copy = Map.fromIterator(context->Map.entries)
  copy->Map.set(toAnyKey(key), {value: toUnknown(value)})
  copy
}
