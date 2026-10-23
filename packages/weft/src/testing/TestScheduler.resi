/***
A `Scheduler.S` that runs nothing until a test says so, with a clock that only moves when the test
moves it. `TestRenderer` uses it.

A slice ends when the clock reaches 5 ms past the slice's start. So a component that calls
`advanceTime(2.0)` while rendering makes a render of three of them yield partway: a test can then
`flushTask` one slice at a time and look at what rendered, or interrupt it with a more urgent update.
*/

include Scheduler.S

/** Moves the clock forward. */
let advanceTime: float => unit

/** Runs the next task, as one time slice. Returns whether there was one. */
let flushTask: unit => bool

/** Runs tasks until none are left. Throws after 10,000, as something keeps scheduling more. */
let flushAll: unit => unit

/** Whether any task is waiting. */
let hasPendingTasks: unit => bool
