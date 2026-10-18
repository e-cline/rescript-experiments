/***
A generic, lazy sequence.

There's no equivalent in Belt or the ReScript standard library, so this
follows the well-known OCaml idiom instead: OCaml's own stdlib `Seq` module represents
a lazy sequence as a thunk that, when forced, produces either "nothing left" or "one
value, plus a thunk for the rest" -- laziness all the way down, not just at the front.
That is what lets `iterate`/`repeat` represent genuinely infinite sequences: nothing
forces more of the sequence than a consumer (e.g. `take`) actually asks for.

Every combinator that returns a `t<'a>` (`map`, `filter`, `take`, `drop`, `append`,
`zip`, ...) is itself lazy: it returns a new thunk immediately, without forcing its
input, so building up a pipeline of them (`seq->filter(...)->map(...)->take(10)`) does
no work until something finally calls `uncons`/`isEmpty`/`forEach`/`reduce`/`toArray`/
`length` on the result. Those last four force the *entire* sequence, so calling them
on an infinite one (e.g. straight off `iterate`, without a `take` first) never returns.

Sequences are not memoized: forcing the same `t<'a>` twice recomputes it, so any side
effects in a generator or callback run again.
*/

/**
One step of a sequence: either nothing left (`Nil`), or a value plus a thunk for the rest.

`node`/`t` are deliberately *not* opaque, unlike this package's other stateful types
(`ImmutableArray.t`, ...). The entire value of a lazy sequence -- the
same as OCaml's own public `Seq` module -- is being able to write a new combinator by
pattern-matching `t()` directly (`switch t() { | Nil => ... | Cons(value, rest) => ... }`)
without this module needing to anticipate it. Hiding the representation would take that
away for no benefit, since there's no invariant a caller could violate by constructing a
`Cons`/`Nil` by hand: any well-formed `unit => node<'a>` is a valid sequence.
*/
type rec node<'a> =
  | Nil
  | Cons('a, unit => node<'a>)

/** A lazy sequence of `'a`: a thunk that, when called, produces the sequence's next `node`. */
type t<'a> = unit => node<'a>

/** The empty sequence. */
let empty: unit => t<'a>

/** A sequence starting with `value`, followed by everything in the given sequence. */
let cons: ('a, t<'a>) => t<'a>

/** A sequence holding exactly one value. */
let singleton: 'a => t<'a>

/**
The sequence's first value together with a sequence of the rest, or `None` if it is
exhausted. Forces exactly one step, no more.
*/
let uncons: t<'a> => option<('a, t<'a>)>

/** Whether the sequence has no values. Forces at most one step. */
let isEmpty: t<'a> => bool

/**
A sequence over the elements of an array. The array is read lazily, so it shouldn't be mutated while
the sequence is still being consumed.
*/
let fromArray: array<'a> => t<'a>

/**
The infinite sequence `seed, f(seed), f(f(seed)), ...`. `f` is called once per element
*after* the seed, and only when that element is actually forced.
*/
let iterate: ('a, 'a => 'a) => t<'a>

/** The infinite sequence of the given value, repeated forever. */
let repeat: 'a => t<'a>

/** Lazily applies the function to every element. */
let map: (t<'a>, 'a => 'b) => t<'b>

/**
Lazily keeps only the elements for which the predicate returns `true`. Forcing the
result on an infinite sequence in which no (further) element matches never returns.
*/
let filter: (t<'a>, 'a => bool) => t<'a>

/**
The first `count` elements (or all of them, if there are fewer). Never forces the input
past the `count`th element, which is what makes it safe to `take` from an infinite
sequence. `count <= 0` gives the empty sequence.
*/
let take: (t<'a>, int) => t<'a>

/** The sequence without its first `count` elements. `count <= 0` gives the sequence unchanged. */
let drop: (t<'a>, int) => t<'a>

/** The longest prefix of elements for which the predicate returns `true`. */
let takeWhile: (t<'a>, 'a => bool) => t<'a>

/** Everything in the first sequence, then everything in the second. */
let append: (t<'a>, t<'a>) => t<'a>

/** Pairs up two sequences elementwise, stopping as soon as either is exhausted. */
let zip: (t<'a>, t<'b>) => t<('a, 'b)>

/**
Forces every remaining element, calling the function on each in order. Never returns if the sequence
is infinite.
*/
let forEach: (t<'a>, 'a => unit) => unit

/**
Forces every remaining element, folding the function over them in order. Never returns if the
sequence is infinite.
*/
let reduce: (t<'a>, 'b, ('b, 'a) => 'b) => 'b

/**
Forces the entire sequence into a plain array. Never returns if the sequence is infinite; `take`
first if that's possible.
*/
let toArray: t<'a> => array<'a>

/**
Forces the entire sequence to count its elements. Never returns if the sequence is
infinite; prefer `isEmpty` if you only need to know whether there are any.
*/
let length: t<'a> => int
