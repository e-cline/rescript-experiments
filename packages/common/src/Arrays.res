// Binary search (`bisectLeft`/`bisectRight`), plus the "immutable positional
// splice" helpers `trees/src/btree/internal/ArrayOps.res` wrote for its
// own private use, generalized here as this package's public, reusable version.
// `trees` itself is deliberately left on its own `ArrayOps` rather than
// switched over to this module, to avoid touching an already-shipped,
// already-benchmarked package (see this package's README for the full reasoning).
//
// Every splice-shaped helper below pre-allocates with
// `Belt.Array.makeUninitializedUnsafe` and fills with a hand-written `for` loop
// rather than `Belt.Array.makeBy(n, i => ...)` -- see
// `trees/src/btree/internal/ArrayOps.res`'s header comment for the benchmark this is
// based on (a per-element closure call is real, consistent overhead once the
// loop body branches).

let insertAt = (array: array<'a>, index: int, value: 'a): array<'a> => {
  let length = Array.length(array)
  let result = Belt.Array.makeUninitializedUnsafe(length + 1)
  for i in 0 to index - 1 {
    Belt.Array.setUnsafe(result, i, Array.getUnsafe(array, i))
  }
  Belt.Array.setUnsafe(result, index, value)
  for i in index to length - 1 {
    Belt.Array.setUnsafe(result, i + 1, Array.getUnsafe(array, i))
  }
  result
}

let removeAt = (array: array<'a>, index: int): array<'a> => {
  let length = Array.length(array)
  let result = Belt.Array.makeUninitializedUnsafe(length - 1)
  for i in 0 to index - 1 {
    Belt.Array.setUnsafe(result, i, Array.getUnsafe(array, i))
  }
  for i in index + 1 to length - 1 {
    Belt.Array.setUnsafe(result, i - 1, Array.getUnsafe(array, i))
  }
  result
}

let replaceAt = (array: array<'a>, index: int, value: 'a): array<'a> => {
  let result = Belt.Array.copy(array)
  Belt.Array.setUnsafe(result, index, value)
  result
}

let chunk = (array: array<'a>, size: int): array<array<'a>> => {
  Debug.debugAssert(size >= 1, ~message=() =>
    `Arrays.chunk: size must be >= 1, got ${Int.toString(size)}`
  )
  let length = Array.length(array)
  if length == 0 {
    []
  } else {
    let chunkCount = (length + size - 1) / size
    Belt.Array.makeBy(chunkCount, i => {
      let from = i * size
      let to_ = min(from + size, length)
      Belt.Array.slice(array, ~offset=from, ~len=to_ - from)
    })
  }
}

let zip = (left: array<'a>, right: array<'b>): array<('a, 'b)> => Belt.Array.zip(left, right)

let zipWith = (left: array<'a>, right: array<'b>, f: ('a, 'b) => 'c): array<'c> =>
  Belt.Array.zipBy(left, right, f)

let partition = (array: array<'a>, predicate: 'a => bool): (array<'a>, array<'a>) => {
  let matched = []
  let unmatched = []
  Array.forEach(array, value =>
    if predicate(value) {
      Array.push(matched, value)
    } else {
      Array.push(unmatched, value)
    }
  )
  (matched, unmatched)
}

let groupBy = (array: array<'a>, getKey: 'a => string): Belt.Map.String.t<array<'a>> =>
  Array.reduce(array, Belt.Map.String.empty, (groups, value) => {
    let key = getKey(value)
    groups->Belt.Map.String.update(key, existing =>
      switch existing {
      | Some(values) => Some(Array.concat(values, [value]))
      | None => Some([value])
      }
    )
  })

let uniqueBy = (array: array<'a>, getKey: 'a => string): array<'a> => {
  let seen = Belt.MutableSet.String.make()
  Array.filter(array, value => {
    let key = getKey(value)
    if seen->Belt.MutableSet.String.has(key) {
      false
    } else {
      seen->Belt.MutableSet.String.add(key)
      true
    }
  })
}

let flatten = (arrays: array<array<'a>>): array<'a> =>
  Array.reduce(arrays, [], (result, array) => Array.concat(result, array))

let bisectLeft = (
  array: array<'a>,
  value: 'a,
  ~compare: ('a, 'a) => int,
  ~lo: int=0,
  ~hi: option<int>=?,
): int => {
  let high = ref(
    switch hi {
    | Some(hi) => hi
    | None => Array.length(array)
    },
  )
  let low = ref(lo)
  while low.contents < high.contents {
    let mid = (low.contents + high.contents) / 2
    if compare(Array.getUnsafe(array, mid), value) < 0 {
      low := mid + 1
    } else {
      high := mid
    }
  }
  low.contents
}

let bisectRight = (
  array: array<'a>,
  value: 'a,
  ~compare: ('a, 'a) => int,
  ~lo: int=0,
  ~hi: option<int>=?,
): int => {
  let high = ref(
    switch hi {
    | Some(hi) => hi
    | None => Array.length(array)
    },
  )
  let low = ref(lo)
  while low.contents < high.contents {
    let mid = (low.contents + high.contents) / 2
    if compare(value, Array.getUnsafe(array, mid)) < 0 {
      high := mid
    } else {
      low := mid + 1
    }
  }
  low.contents
}
