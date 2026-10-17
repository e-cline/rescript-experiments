/***
When work runs: the reconciler's second pluggable piece (with `HostConfig`).

The reconciler renders transitions in scheduler tasks, and checks `shouldYield` between units of
work; when it says yes, the render stops where it is and continues in a new task. `Default` runs
tasks in macrotasks and yields every 5 ms, so a long render doesn't block input. `TestScheduler`
runs them only when a test says so.
*/

/** How urgent a task is: more urgent tasks run first, and each kind times out sooner. */
type priority =
  | Immediate
  | UserBlocking
  | Normal
  | Low
  | Idle

module type S = {
  type task

  /** Runs `callback` in a later task, ordered by priority and then by when it was scheduled. */
  let scheduleCallback: (priority, unit => unit) => task

  /** Stops a task that hasn't run yet from running. */
  let cancelCallback: task => unit

  /** Whether the current task has used up its time slice and should return to the event loop. */
  let shouldYield: unit => bool

  /** The time, in milliseconds. */
  let now: unit => float
}

/**
The scheduler `Reconciler.Make` uses. Tasks wait in a priority queue (ordered by expiration time,
which is the time scheduled plus a timeout for the priority) and run in macrotasks (`setImmediate`
where it exists, then `MessageChannel`, then `setTimeout`), several per macrotask until 5 ms have
passed. A task past its expiration runs even when the slice is used up.
*/
module Default: {
  include S

  /** How long a task of `priority` may wait before it runs even when the time slice is used up. */
  let timeout: priority => float
}
