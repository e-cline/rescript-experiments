@@weft.server

/***
What every slow "service" the pages call waits on, by name (`rail:deals`, `stock:p3`,
`reviews:p3`...): the synthetic latency the streaming is there to hide.

- `Random` (the default for `vp dev` and `vp run start`): each call waits a random time in its
  kind's range, from a seeded generator (`WEFT_SHOP_SEED`), and the flaky services
  (recommendations, questions) fail now and then (`WEFT_SHOP_FAIL_RATE`, 0.2 by default).
- `Fixed`: each kind waits the middle of its range, and nothing fails.
- `Off`: nothing waits.
- `Manual` (the tests'): nothing opens until the test releases it, by name or by prefix, or fails it,
  so the order things finish in is the test's choice.

`WEFT_SHOP_LATENCY` picks the mode (`random`, `fixed`, `off` or `manual`). A call whose request was
aborted (the client navigated away) stops waiting, and is recorded as abandoned.
*/

/** A request's `AbortSignal`. */
type signal

@get external aborted: signal => bool = "aborted"
@send external onAbort: (signal, @as("abort") _, unit => unit) => unit = "addEventListener"

type mode = Random | Fixed | Off | Manual

@val @scope(("process", "env")) external modeFlag: Nullable.t<string> = "WEFT_SHOP_LATENCY"
@val @scope(("process", "env")) external seedFlag: Nullable.t<string> = "WEFT_SHOP_SEED"
@val @scope(("process", "env")) external failRateFlag: Nullable.t<string> = "WEFT_SHOP_FAIL_RATE"

let modeOf = flag =>
  switch flag {
  | Some("fixed") => Fixed
  | Some("off") => Off
  | Some("manual") => Manual
  | _ => Random
  }

let mode = ref(modeOf(modeFlag->Nullable.toOption))

let failRate =
  failRateFlag->Nullable.toOption->Option.flatMap(rate => Float.fromString(rate))->Option.getOr(0.2)

// mulberry32: small, and the same sequence for the same seed everywhere.
let state = ref(
  seedFlag->Nullable.toOption->Option.flatMap(seed => Int.fromString(seed))->Option.getOr(1),
)

let random: unit => float = %raw(`function (state) {
  return function () {
    let t = (state.contents = (state.contents + 0x6d2b79f5) | 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}`)(state)

let kindOf = name => name->String.split(":")->Array.getUnsafe(0)

/** How long each kind of call takes, in milliseconds: the least and the most. */
let range = name =>
  switch kindOf(name) {
  | "layout" => (50, 300)
  | "block" => (100, 900)
  | "rail" => (200, 1500)
  | "stock" => (100, 1200)
  | "offer" => (100, 600)
  | "reviews" => (300, 2000)
  | "recs" => (400, 1800)
  | "qa" => (200, 1000)
  | "facets" => (100, 700)
  | "results" => (200, 1400)
  | "search" => (50, 400)
  | "status" => (50, 300)
  | "estimate" => (300, 1500)
  | _ => (0, 100)
  }

/** The services that fail now and then (in `Random` mode), and what they say when they do. */
let failure = name =>
  switch kindOf(name) {
  | "recs" => Some("the recommendations service timed out")
  | "qa" => Some("the questions service is unavailable")
  | _ => None
  }

type waiter = {
  id: string,
  name: string,
  /** Settles the call: with `None` it goes ahead, with `Some(message)` it fails so. */
  settle: option<string> => unit,
}

let waiters: array<waiter> = []
let opened: Set.t<string> = Set.make()
let openPrefixes: array<string> = []
let failed: Map.t<string, string> = Map.make()
/** Gates closed again by `hold`, whatever prefix opened them. */
let held: Set.t<string> = Set.make()
let abandoned: array<string> = []
let count = ref(0)

let remove = id => {
  let index = waiters->Array.findIndex(waiter => waiter.id == id)
  if index >= 0 {
    waiters->Array.splice(~start=index, ~remove=1, ~insert=[])
  }
}

let isOpen = name =>
  !(held->Set.has(name)) &&
  (opened->Set.has(name) || openPrefixes->Array.some(prefix => name->String.startsWith(prefix)))

let timer = (ms, ~signal) =>
  Promise.make((resolve, _) => {
    let handle = setTimeout(() => resolve(), ms)
    signal->onAbort(() => clearTimeout(handle))
  })

/** How a call to `name` turns out: `None` to go ahead, `Some(message)` to fail. */
let outcome = (name, ~signal): promise<option<string>> =>
  switch mode.contents {
  | Off => Promise.resolve(None)
  | Fixed =>
    let (low, high) = range(name)
    timer((low + high) / 2, ~signal)->Promise.thenResolve(() => None)
  | Random =>
    let (low, high) = range(name)
    let ms = low + Float.toInt(random() *. Int.toFloat(high - low))
    let fails = failure(name)->Option.filter(_ => random() < failRate)
    timer(ms, ~signal)->Promise.thenResolve(() => fails)
  | Manual =>
    switch failed->Map.get(name) {
    | Some(message) => Promise.resolve(Some(message))
    | None if isOpen(name) => Promise.resolve(None)
    | None =>
      Promise.make((resolve, _) => {
        count := count.contents + 1
        let id = `${name}#${Int.toString(count.contents)}`
        waiters->Array.push({
          id,
          name,
          settle: outcome => {
            remove(id)
            resolve(outcome)
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
  }

/**
Waits for `name`, then resolves, or rejects with the service's error. A call whose `signal` aborts
never settles: its request is gone.
*/
let wait = async (name, ~signal: signal) =>
  switch await outcome(name, ~signal) {
  | Some(message) => JsError.throwWithMessage(message)
  | None => ()
  }

/** `wait`, then `value()`. */
let after = async (name, ~signal, value) => {
  await wait(name, ~signal)
  value()
}

/**
Opens `gate`: a name (`stock:p1`) opens it for every call waiting on it and every later one; a
waiter's id (`stock:p1#3`, from `waiting`) releases just that call.
*/
let release = gate =>
  if gate->String.includes("#") {
    waiters->Array.find(waiter => waiter.id == gate)->Option.forEach(waiter => waiter.settle(None))
  } else {
    held->Set.delete(gate)->ignore
    opened->Set.add(gate)
    waiters
    ->Array.filter(waiter => waiter.name == gate)
    ->Array.forEach(waiter => waiter.settle(None))
  }

/** Opens every gate whose name starts with `prefix`, now and later (`""`: all of them). */
let releasePrefix = prefix => {
  openPrefixes->Array.push(prefix)
  waiters
  ->Array.filter(waiter => waiter.name->String.startsWith(prefix))
  ->Array.forEach(waiter => waiter.settle(None))
}

/** Makes every call to `gate`, waiting or later, fail with `message`, until `heal`. */
let fail = (gate, message) => {
  failed->Map.set(gate, message)
  waiters
  ->Array.filter(waiter => waiter.name == gate)
  ->Array.forEach(waiter => waiter.settle(Some(message)))
}

/** Closes `gate` again, for calls from now on, however it was opened (until it's released). */
let hold = gate => {
  opened->Set.delete(gate)->ignore
  held->Set.add(gate)
}

/** Undoes `fail`: the gate is closed again (until released). */
let heal = gate => {
  failed->Map.delete(gate)->ignore
  opened->Set.delete(gate)->ignore
}

/** The calls waiting, by waiter id. */
let waiting = () => waiters->Array.map(waiter => waiter.id)

/** Back to `Manual`, with every gate closed, nothing waiting, failing or abandoned. */
let reset = () => {
  mode := Manual
  waiters->Array.splice(~start=0, ~remove=Array.length(waiters), ~insert=[])
  abandoned->Array.splice(~start=0, ~remove=Array.length(abandoned), ~insert=[])
  openPrefixes->Array.splice(~start=0, ~remove=Array.length(openPrefixes), ~insert=[])
  opened->Set.clear
  held->Set.clear
  failed->Map.clear
  count := 0
}
