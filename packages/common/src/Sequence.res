// See `Sequence.resi` for what a `Sequence.t` is and how its laziness works;
// the comments here are implementation notes.

type rec node<'a> =
  | Nil
  | Cons('a, unit => node<'a>)

type t<'a> = unit => node<'a>

let empty = (): t<'a> => () => Nil

let cons = (value: 'a, rest: t<'a>): t<'a> => () => Cons(value, rest)

let singleton = (value: 'a): t<'a> => cons(value, empty())

let uncons = (t: t<'a>): option<('a, t<'a>)> =>
  switch t() {
  | Nil => None
  | Cons(value, rest) => Some((value, rest))
  }

let isEmpty = (t: t<'a>): bool =>
  switch t() {
  | Nil => true
  | Cons(_, _) => false
  }

let fromArray = (array: array<'a>): t<'a> => {
  let rec fromIndex = (index: int): t<'a> =>
    () =>
      if index >= Array.length(array) {
        Nil
      } else {
        Cons(Array.getUnsafe(array, index), fromIndex(index + 1))
      }
  fromIndex(0)
}

// Applying `f` is deferred into the *next* thunk (`() => go(f(value))()`),
// rather than writing `Cons(value, go(f(value)))`. The latter would call `f` as
// soon as the current element is forced, one element earlier than anything
// actually needs it: function application is strict, so `go(f(value))` has to
// evaluate `f(value)` right away just to build its (lazy) result. Wrapping it in
// `() => ...` defers that evaluation until the wrapper itself is forced.
let iterate = (seed: 'a, f: 'a => 'a): t<'a> => {
  let rec go = (value: 'a): t<'a> => () => Cons(value, () => go(f(value))())
  go(seed)
}

let repeat = (value: 'a): t<'a> => {
  let rec self = () => Cons(value, self)
  self
}

let rec map = (t: t<'a>, f: 'a => 'b): t<'b> =>
  () =>
    switch t() {
    | Nil => Nil
    | Cons(value, rest) => Cons(f(value), map(rest, f))
    }

let rec filter = (t: t<'a>, predicate: 'a => bool): t<'a> =>
  () =>
    switch t() {
    | Nil => Nil
    | Cons(value, rest) =>
      if predicate(value) {
        Cons(value, filter(rest, predicate))
      } else {
        filter(rest, predicate)()
      }
    }

let rec take = (t: t<'a>, count: int): t<'a> =>
  () =>
    if count <= 0 {
      Nil
    } else {
      switch t() {
      | Nil => Nil
      | Cons(value, rest) => Cons(value, take(rest, count - 1))
      }
    }

let rec drop = (t: t<'a>, count: int): t<'a> =>
  () =>
    if count <= 0 {
      t()
    } else {
      switch t() {
      | Nil => Nil
      | Cons(_, rest) => drop(rest, count - 1)()
      }
    }

let rec takeWhile = (t: t<'a>, predicate: 'a => bool): t<'a> =>
  () =>
    switch t() {
    | Nil => Nil
    | Cons(value, rest) =>
      if predicate(value) {
        Cons(value, takeWhile(rest, predicate))
      } else {
        Nil
      }
    }

let rec append = (first: t<'a>, second: t<'a>): t<'a> =>
  () =>
    switch first() {
    | Nil => second()
    | Cons(value, rest) => Cons(value, append(rest, second))
    }

let rec zip = (a: t<'a>, b: t<'b>): t<('a, 'b)> =>
  () =>
    switch (a(), b()) {
    | (Cons(valueA, restA), Cons(valueB, restB)) => Cons((valueA, valueB), zip(restA, restB))
    | _ => Nil
    }

let rec forEach = (t: t<'a>, f: 'a => unit): unit =>
  switch t() {
  | Nil => ()
  | Cons(value, rest) =>
    f(value)
    forEach(rest, f)
  }

let rec reduce = (t: t<'a>, initial: 'b, f: ('b, 'a) => 'b): 'b =>
  switch t() {
  | Nil => initial
  | Cons(value, rest) => reduce(rest, f(initial, value), f)
  }

let toArray = (t: t<'a>): array<'a> => {
  let result = []
  forEach(t, value => Array.push(result, value))
  result
}

let length = (t: t<'a>): int => reduce(t, 0, (count, _) => count + 1)
