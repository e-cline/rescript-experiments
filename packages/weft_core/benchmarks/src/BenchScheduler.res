/***
A scheduler for the benchmarks: tasks run only when `flushAll` runs them, and a task's slice ends
after every 100 `shouldYield` checks (one per unit of work), so a transition's render yields as
often as a real one might, on any machine, without measuring the clock.
*/

type task = {callback: unit => unit, mutable cancelled: bool}

let unitsPerSlice = 100
let tasks: array<task> = []
let checks = ref(0)

let scheduleCallback = (_: WeftCore.Scheduler.priority, callback) => {
  let task = {callback, cancelled: false}
  tasks->Array.push(task)
  task
}

let cancelCallback = task => task.cancelled = true

let shouldYield = () => {
  checks := checks.contents + 1
  checks.contents >= unitsPerSlice
}

let now = () => 0.0

/** Runs tasks, each as a fresh slice, until there are none. Returns how many slices ran. */
let flushAll = () => {
  let slices = ref(0)
  while Array.length(tasks) > 0 {
    let task = tasks->Array.shift->Option.getUnsafe
    if !task.cancelled {
      checks := 0
      slices := slices.contents + 1
      task.callback()
    }
  }
  slices.contents
}
