// See `ImmutableArray.resi` for what it does and doesn't
// promise. `t<'a>` is a plain `array<'a>` here -- the `.resi` hides that so
// nothing outside this file can mutate it.
//
// Every splice-shaped operation delegates to `Arrays`' helpers, which avoid
// `Belt.Array.makeBy`'s per-element closure call where it matters (see
// `Arrays.res`'s header comment).

type t<'a> = array<'a>

// A function, not a plain value, specifically so it stays polymorphic: a
// `let empty: t<'a> = []` would hit the value restriction and monomorphize `'a`
// at the first use site (see the root `RESCRIPT.md`'s gap #15).
let make = (): t<'a> => []
let fromArray = (array: array<'a>): t<'a> => Belt.Array.copy(array)
let toArray = (t: t<'a>): array<'a> => Belt.Array.copy(t)

let length = (t: t<'a>): int => Array.length(t)
let isEmpty = (t: t<'a>): bool => Array.length(t) == 0

let get = (t: t<'a>, index: int): option<'a> => t[index]
let getExn = (t: t<'a>, index: int): 'a =>
  switch t[index] {
  | Some(value) => value
  | None =>
    Debug.fail(~message=() =>
      `ImmutableArray.getExn: index ${Int.toString(index)} out of bounds (length ${Int.toString(
          Array.length(t),
        )})`
    )
  }

let set = (t: t<'a>, index: int, value: 'a): t<'a> => Arrays.replaceAt(t, index, value)
let insertAt = (t: t<'a>, index: int, value: 'a): t<'a> => Arrays.insertAt(t, index, value)
let removeAt = (t: t<'a>, index: int): t<'a> => Arrays.removeAt(t, index)

let push = (t: t<'a>, value: 'a): t<'a> => Arrays.insertAt(t, Array.length(t), value)
let pop = (t: t<'a>): t<'a> =>
  switch Array.length(t) {
  | 0 => t
  | length => Arrays.removeAt(t, length - 1)
  }

let first = (t: t<'a>): option<'a> => t[0]
let last = (t: t<'a>): option<'a> =>
  switch Array.length(t) {
  | 0 => None
  | length => t[length - 1]
  }

let slice = (t: t<'a>, ~start: int, ~end_: option<int>=?): t<'a> => {
  let length = Array.length(t)
  let stop = switch end_ {
  | Some(end_) => min(end_, length)
  | None => length
  }
  if start >= stop {
    []
  } else {
    Belt.Array.slice(t, ~offset=start, ~len=stop - start)
  }
}

let concat = (left: t<'a>, right: t<'a>): t<'a> => Belt.Array.concat(left, right)

let map = (t: t<'a>, f: 'a => 'b): t<'b> => Array.map(t, f)
let filter = (t: t<'a>, predicate: 'a => bool): t<'a> => Array.filter(t, predicate)
let reduce = (t: t<'a>, initial: 'b, f: ('b, 'a) => 'b): 'b => Array.reduce(t, initial, f)
let forEach = (t: t<'a>, f: 'a => unit): unit => Array.forEach(t, f)
let some = (t: t<'a>, predicate: 'a => bool): bool => Array.some(t, predicate)
let every = (t: t<'a>, predicate: 'a => bool): bool => Array.every(t, predicate)
let find = (t: t<'a>, predicate: 'a => bool): option<'a> => Array.find(t, predicate)
let findIndex = (t: t<'a>, predicate: 'a => bool): option<int> =>
  switch Array.findIndexOpt(t, predicate) {
  | Some(index) => Some(index)
  | None => None
  }

let equal = (a: t<'a>, b: t<'a>, elementEqual: ('a, 'a) => bool): bool => {
  let length = Array.length(a)
  if length != Array.length(b) {
    false
  } else {
    let index = ref(0)
    let allEqual = ref(true)
    while allEqual.contents && index.contents < length {
      if !elementEqual(Array.getUnsafe(a, index.contents), Array.getUnsafe(b, index.contents)) {
        allEqual := false
      }
      index := index.contents + 1
    }
    allEqual.contents
  }
}
