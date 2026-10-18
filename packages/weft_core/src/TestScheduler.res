type task = {
  id: int,
  callback: unit => unit,
  expiration: float,
  mutable cancelled: bool,
}

let sliceMs = 5.0
let currentTime = ref(0.0)
let deadline = ref(0.0)
let nextId = ref(0)
let tasks: array<task> = []

let now = () => currentTime.contents
let advanceTime = ms => currentTime := currentTime.contents +. ms
let shouldYield = () => currentTime.contents >= deadline.contents

let scheduleCallback = (priority, callback) => {
  let task = {
    id: nextId.contents,
    callback,
    expiration: currentTime.contents +. Scheduler.Default.timeout(priority),
    cancelled: false,
  }
  nextId := nextId.contents + 1
  tasks->Array.push(task)
  task
}

let cancelCallback = task => task.cancelled = true

let hasPendingTasks = () => tasks->Array.some(task => !task.cancelled)

/** Removes and returns the next task to run: earliest expiration, then earliest scheduled. */
let takeNext = () => {
  let live = tasks->Array.filter(task => !task.cancelled)
  tasks->Array.splice(~start=0, ~remove=Array.length(tasks), ~insert=[])
  switch live->Array.toSorted((a, b) =>
    a.expiration == b.expiration ? Int.toFloat(a.id - b.id) : a.expiration -. b.expiration
  ) {
  | [] => None
  | sorted =>
    let next = sorted->Array.getUnsafe(0)
    sorted->Array.forEachWithIndex((task, index) =>
      if index > 0 {
        tasks->Array.push(task)
      }
    )
    Some(next)
  }
}

let flushTask = () =>
  switch takeNext() {
  | Some(task) =>
    deadline := currentTime.contents +. sliceMs
    task.callback()
    true
  | None => false
  }

let maxTasks = 10000

let flushAll = () => {
  let count = ref(0)
  while flushTask() {
    count := count.contents + 1
    if count.contents > maxTasks {
      JsError.throwWithMessage("TestScheduler: tasks keep scheduling more tasks")
    }
  }
}
