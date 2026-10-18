/***
A persistent (immutable) priority queue, backed by a leftist heap: every operation
returns a new queue and leaves the original untouched.

There's no immutable heap in Belt or OCaml's stdlib, so this follows the
well-known purely-functional leftist-heap algorithm. `enqueue` and `dequeue` are
`O(log n)`; for a mutable queue, see `MutablePriorityQueue`.

As in `MutablePriorityQueue`, priority is identified via `Belt.Id.comparable`: negative means
the first argument has *higher* priority, so an ordinary ascending comparator gives a
min-heap. Elements of equal priority are dequeued in an unspecified order.
*/

/** A persistent priority queue of `'a`, ordered by the comparator identified by `'id`. */
type t<'a, 'id>

/** An empty queue, ordered by the comparator in `id`. */
let make: (~id: Belt.Id.comparable<'a, 'id>) => t<'a, 'id>

/**
A queue holding `items`. Built by enqueueing each item in turn, so `O(n log n)`
(unlike `MutablePriorityQueue.fromArray`'s `O(n)`).
*/
let fromArray: (array<'a>, ~id: Belt.Id.comparable<'a, 'id>) => t<'a, 'id>

/** A queue with the given value added, in `O(log n)`. */
let enqueue: (t<'a, 'id>, 'a) => t<'a, 'id>

/** The highest-priority value, or `None` if the queue is empty. */
let peek: t<'a, 'id> => option<'a>

/** Like `peek`, but throws if the queue is empty. */
let peekExn: t<'a, 'id> => 'a

/**
The highest-priority value together with the queue that remains once it is removed, or
`None` if the queue is empty. `O(log n)`.
*/
let dequeue: t<'a, 'id> => option<('a, t<'a, 'id>)>

/** Like `dequeue`, but throws if the queue is empty. */
let dequeueExn: t<'a, 'id> => ('a, t<'a, 'id>)

/** Whether the queue holds no values. */
let isEmpty: t<'a, 'id> => bool

/** The number of values in the queue. */
let size: t<'a, 'id> => int

/**
Every value, in priority order (the same order repeated `dequeue`s would give). `O(n log n)`;
for tests and diagnostics. The queue itself is unchanged.
*/
let toArray: t<'a, 'id> => array<'a>
