/***
A mutable priority queue, backed by an array-based binary heap.

Belt has no priority queue/heap of its own (`Belt.MutableStack`/`Belt.MutableQueue`
are unordered; `Belt.HashMap`/`Belt.Map`/etc. are key/value structures, not heaps),
so this fills a genuine gap.

Rather than by a bare comparator function, priority is identified via
`Belt.Id.comparable` -- the same mechanism `Belt.Set`/`Belt.Map` use, and the
convention `res_b_tree` established for this repo's other collections. The comparator
follows the usual convention: negative means the first argument has *higher* priority
than the second, zero means equal priority, positive means the second has higher
priority. So an ordinary ascending comparator gives a min-heap (the smallest element is
dequeued first). Elements of equal priority are
dequeued in an unspecified order.
*/

/** A mutable priority queue of `'a`, ordered by the comparator identified by `'id`. */
type t<'a, 'id>

/** An empty queue, ordered by the comparator in `id`. */
let make: (~id: Belt.Id.comparable<'a, 'id>) => t<'a, 'id>

/**
A queue holding a copy of `items` (the array itself is not modified), built in `O(n)`
time (heapify) rather than by `n` sequential `O(log n)` `enqueue` calls.
*/
let fromArray: (array<'a>, ~id: Belt.Id.comparable<'a, 'id>) => t<'a, 'id>

/** Adds a value in `O(log n)`. */
let enqueue: (t<'a, 'id>, 'a) => unit

/**
Removes and returns the highest-priority value in `O(log n)`, or `None` if the queue is empty.
*/
let dequeue: t<'a, 'id> => option<'a>

/** Like `dequeue`, but throws if the queue is empty. */
let dequeueExn: t<'a, 'id> => 'a

/** The highest-priority value, without removing it, or `None` if the queue is empty. */
let peek: t<'a, 'id> => option<'a>

/** Like `peek`, but throws if the queue is empty. */
let peekExn: t<'a, 'id> => 'a

/** Whether the queue holds no values. */
let isEmpty: t<'a, 'id> => bool

/** The number of values in the queue. */
let size: t<'a, 'id> => int

/** Removes every value. */
let clear: t<'a, 'id> => unit

/**
A copy of the heap's current backing array, in heap order (*not* sorted order). For
tests and diagnostics, not for anything that depends on element order.
*/
let toArray: t<'a, 'id> => array<'a>
