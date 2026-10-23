@@weft.server

/***
What the database's queries wait on, by name (`body:1`, `comments:1`, ...): in `vp dev`, a timer
for each, so the streaming is visible by hand; in tests, nothing until the test opens the gate
(`tests/FakeDbControl.res`), so the order things finish in is the test's choice, not a timer's.

A query whose request was aborted (the client navigated away) stops waiting, and is recorded as
abandoned.
*/

/** A request's `AbortSignal`. */
type signal

@get external aborted: signal => bool = "aborted"
@send external onAbort: (signal, @as("abort") _, unit => unit) => unit = "addEventListener"

type mode =
  /** Each gate opens after a delay. */
  | Timers
  /** A gate opens when it's released. */
  | Manual

let mode = ref(Timers)

/** How long each kind of gate takes to open in `Timers` mode. */
let delay = name =>
  switch name->String.split(":")->Array.getUnsafe(0) {
  | "body" => 400
  | "comments" => 800
  | "related" => 1200
  | _ => 0
  }

type waiter = {id: string, name: string, release: unit => unit}

let waiters: array<waiter> = []
let opened: Set.t<string> = Set.make()
let abandoned: array<string> = []
let count = ref(0)

let remove = id => {
  let index = waiters->Array.findIndex(waiter => waiter.id == id)
  if index >= 0 {
    waiters->Array.splice(~start=index, ~remove=1, ~insert=[])
  }
}

/** Waits for the gate `name`, or for `signal` to abort (which never resolves: the request is gone). */
let wait = (name, ~signal: signal) =>
  switch mode.contents {
  | Timers => Promise.make((resolve, _) => setTimeout(() => resolve(), delay(name))->ignore)
  | Manual if opened->Set.has(name) => Promise.resolve()
  | Manual =>
    Promise.make((resolve, _) => {
      count := count.contents + 1
      let id = `${name}#${Int.toString(count.contents)}`
      waiters->Array.push({
        id,
        name,
        release: () => {
          remove(id)
          resolve()
        },
      })
      signal->onAbort(() =>
        if waiters->Array.some(waiter => waiter.id == id) {
          remove(id)
          abandoned->Array.push(id)
        }
      )
    })
  }

/**
Opens `gate`: a name (`comments:1`) opens it for every query waiting on it and every later one; a
waiter's id (`comments:1#3`, from `waiting`) releases just that query.
*/
let release = gate =>
  if gate->String.includes("#") {
    waiters->Array.find(waiter => waiter.id == gate)->Option.forEach(waiter => waiter.release())
  } else {
    opened->Set.add(gate)
    waiters->Array.filter(waiter => waiter.name == gate)->Array.forEach(waiter => waiter.release())
  }

/** The queries waiting, by waiter id. */
let waiting = () => waiters->Array.map(waiter => waiter.id)

/** Back to `Manual` with every gate closed, nothing waiting and nothing abandoned. */
let reset = () => {
  mode := Manual
  waiters->Array.splice(~start=0, ~remove=Array.length(waiters), ~insert=[])
  abandoned->Array.splice(~start=0, ~remove=Array.length(abandoned), ~insert=[])
  opened->Set.clear
  count := 0
}
