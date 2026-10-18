type priority =
  | Immediate
  | UserBlocking
  | Normal
  | Low
  | Idle

module type S = {
  type task
  let scheduleCallback: (priority, unit => unit) => task
  let cancelCallback: task => unit
  let shouldYield: unit => bool
  let now: unit => float
}

module Default = {
  type task = {
    id: int,
    callback: unit => unit,
    expiration: float,
    mutable cancelled: bool,
  }

  /** How long a task may wait before it runs regardless of the time slice. */
  let timeout = (priority: priority) =>
    switch priority {
    | Immediate => -1.0
    | UserBlocking => 250.0
    | Normal => 5000.0
    | Low => 10000.0
    | Idle => 1073741823.0
    }

  module TaskOrder = Belt.Id.MakeComparable({
    type t = task
    let cmp = (a: task, b: task) =>
      if a.expiration < b.expiration {
        -1
      } else if a.expiration > b.expiration {
        1
      } else {
        a.id - b.id
      }
  })

  @val external performance: {"now": unit => float} = "performance"
  let now = () => performance["now"]()

  let frameMs = 5.0
  let queue = PriorityQueue.MutablePriorityQueue.make(~id=module(TaskOrder))
  let nextId = ref(0)
  let deadline = ref(0.0)
  let isLoopScheduled = ref(false)

  let shouldYield = () => now() >= deadline.contents

  @val external globalThis: dict<unknown> = "globalThis"
  @val external setImmediate: (unit => unit) => unit = "setImmediate"
  @val external setTimeout: (unit => unit, int) => unit = "setTimeout"
  type channel
  type port
  @new external makeChannel: unit => channel = "MessageChannel"
  @get external port1: channel => port = "port1"
  @get external port2: channel => port = "port2"
  @set external setOnMessage: (port, unit => unit) => unit = "onmessage"
  @send external postMessage: (port, Nullable.t<unknown>) => unit = "postMessage"

  let has = name => Type.typeof(globalThis->Dict.getUnsafe(name)) == #function

  /** The next task in the queue to run, dropping cancelled ones. */
  let rec peekLive = () =>
    switch PriorityQueue.MutablePriorityQueue.peek(queue) {
    | Some(task) if task.cancelled =>
      PriorityQueue.MutablePriorityQueue.dequeue(queue)->ignore
      peekLive()
    | next => next
    }

  let runLoop = ref(() => ())

  // Node and jsdom have `setImmediate`, which doesn't hold the process open the way a
  // `MessageChannel` port with a listener does; browsers have `MessageChannel`, which (unlike
  // `setTimeout`) isn't clamped to 4 ms.
  let requestLoop = if has("setImmediate") {
    () => setImmediate(() => runLoop.contents())
  } else if has("MessageChannel") {
    let channel = makeChannel()
    setOnMessage(port1(channel), () => runLoop.contents())
    () => postMessage(port2(channel), Nullable.null)
  } else {
    () => setTimeout(() => runLoop.contents(), 0)
  }

  let scheduleLoop = () =>
    if !isLoopScheduled.contents {
      isLoopScheduled := true
      requestLoop()
    }

  runLoop :=
    (
      () => {
        isLoopScheduled := false
        deadline := now() +. frameMs
        let running = ref(true)
        while running.contents {
          switch peekLive() {
          | Some(task) if task.expiration <= now() || !shouldYield() =>
            PriorityQueue.MutablePriorityQueue.dequeue(queue)->ignore
            try task.callback() catch {
            | error =>
              // Keep the other tasks going, then let the error surface.
              scheduleLoop()
              throw(error)
            }
          | Some(_) =>
            scheduleLoop()
            running := false
          | None => running := false
          }
        }
      }
    )

  let scheduleCallback = (priority, callback) => {
    let task = {
      id: nextId.contents,
      callback,
      expiration: now() +. timeout(priority),
      cancelled: false,
    }
    nextId := nextId.contents + 1
    PriorityQueue.MutablePriorityQueue.enqueue(queue, task)
    scheduleLoop()
    task
  }

  let cancelCallback = task => task.cancelled = true
}
