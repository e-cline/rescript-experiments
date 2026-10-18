open Vitest

module Effect = EffectBase.Make(Scheduler.Sync)

describe("EffectBase.Make(Scheduler.Sync)", () => {
  test("runs immediately on creation", t => {
    let ran = ref(false)
    Effect.make(() => ran := true)->ignore
    t->expect(ran.contents)->Expect.toBeTruthy
  })

  test("reruns synchronously when a dependency it read changes", t => {
    let a = Atom.make(1)
    let seen = []
    Effect.make(() => Array.push(seen, Atom.get(a)))->ignore
    Atom.set(a, 2)
    Atom.set(a, 3)
    t->expect(seen)->Expect.toEqual([1, 2, 3])
  })

  test("does not rerun for an atom it doesn't (or no longer) reads", t => {
    let switch_ = Atom.make(true)
    let onTrue = Atom.make("a")
    let onFalse = Atom.make("b")
    let runs = ref(0)
    Effect.make(
      () => {
        runs := runs.contents + 1
        (Atom.get(switch_) ? Atom.get(onTrue) : Atom.get(onFalse))->ignore
      },
    )->ignore
    t->expect(runs.contents)->Expect.toBe(1)
    Atom.set(switch_, false)
    t->expect(runs.contents)->Expect.toBe(2)
    Atom.set(onTrue, "z") // no longer read; must not trigger a rerun
    t->expect(runs.contents)->Expect.toBe(2)
    Atom.set(onFalse, "y")
    t->expect(runs.contents)->Expect.toBe(3)
  })

  test("only reruns once per batch of writes, and sees the final values", t => {
    let a = Atom.make(1)
    let b = Atom.make(10)
    let seen = []
    Effect.make(() => Array.push(seen, Atom.get(a) + Atom.get(b)))->ignore
    Batch.run(
      () => {
        Atom.set(a, 2)
        Atom.set(b, 20)
      },
    )
    t->expect(seen)->Expect.toEqual([11, 22])
  })

  test("dispose stops it from rerunning", t => {
    let a = Atom.make(1)
    let runs = ref(0)
    let effect = Effect.make(
      () => {
        runs := runs.contents + 1
        Atom.get(a)->ignore
      },
    )
    Effect.dispose(effect)
    Atom.set(a, 2)
    t->expect(runs.contents)->Expect.toBe(1)
  })

  test("an effect reading a computed sees it settle to a consistent, glitch-free value", t => {
    let a = Atom.make(1)
    let left = Computed.make(() => Atom.get(a) + 1)
    let right = Computed.make(() => Atom.get(a) * 10)
    let seen = []
    Effect.make(() => Array.push(seen, (Signal.get(left), Signal.get(right))))->ignore
    Atom.set(a, 2)
    // Never (3, 10) or (2, 20) -- only ever fully-consistent pairs.
    t->expect(seen)->Expect.toEqual([(2, 10), (3, 20)])
  })

  test("does not rerun when a computed it reads recomputes to an equal value", t => {
    let a = Atom.make(1)
    let parity = Computed.make(() => mod(Atom.get(a), 2))
    let seen = []
    Effect.make(() => Array.push(seen, Signal.get(parity)))->ignore
    Atom.set(a, 3) // still odd
    Atom.set(a, 5) // still odd
    t->expect(seen)->Expect.toEqual([1])
    Atom.set(a, 6)
    t->expect(seen)->Expect.toEqual([1, 0])
  })

  test("reruns after writing an atom it has already read, until it settles", t => {
    let a = Atom.make(0)
    let seen = []
    Effect.make(
      () => {
        let value = Atom.get(a)
        Array.push(seen, value)
        if value < 3 {
          Atom.set(a, value + 1)
        }
      },
    )->ignore
    t->expect(seen)->Expect.toEqual([0, 1, 2, 3])
  })

  test("effects triggered from inside an effect run after the ones already due", t => {
    let a = Atom.make(0)
    let b = Atom.make(0)
    let order = []
    Effect.make(
      () => {
        Array.push(order, `first:${Int.toString(Atom.get(a))}`)
        Atom.set(b, Atom.get(a))
      },
    )->ignore
    Effect.make(() => Array.push(order, `second:${Int.toString(Atom.get(a))}`))->ignore
    Effect.make(() => Array.push(order, `third:${Int.toString(Atom.get(b))}`))->ignore
    Array.splice(order, ~start=0, ~remove=Array.length(order), ~insert=[])
    Atom.set(a, 1)
    t->expect(order)->Expect.toEqual(["first:1", "second:1", "third:1"])
  })
})

describe("EffectBase.make with a custom scheduler", () => {
  // A scheduler that only queues, leaving the test to decide when effects rerun.
  let makeQueue = () => {
    let queue: array<EffectBase.t> = []
    let flush = () => {
      let due = Array.copy(queue)
      Array.splice(queue, ~start=0, ~remove=Array.length(queue), ~insert=[])
      Array.forEach(due, EffectBase.run)
    }
    (queue, flush)
  }

  test("runs immediately on creation, without consulting the scheduler", t => {
    let (queue, _) = makeQueue()
    let runs = ref(0)
    EffectBase.make(
      ~scheduler=effect => Array.push(queue, effect),
      () => runs := runs.contents + 1,
    )->ignore
    t->expect(runs.contents)->Expect.toBe(1)
    t->expect(Array.length(queue))->Expect.toBe(0)
  })

  test("is scheduled once however many writes land before it reruns", t => {
    let (queue, flush) = makeQueue()
    let a = Atom.make(1)
    let b = Atom.make(10)
    let seen = []
    EffectBase.make(
      ~scheduler=effect => Array.push(queue, effect),
      () => Array.push(seen, Atom.get(a) + Atom.get(b)),
    )->ignore
    Atom.set(a, 2)
    Atom.set(b, 20)
    Atom.set(a, 3)
    t->expect(seen)->Expect.toEqual([11]) // nothing reruns until the scheduler says so
    t->expect(Array.length(queue))->Expect.toBe(1)
    flush()
    t->expect(seen)->Expect.toEqual([11, 23])
    // Idle again, so the next change schedules it again.
    Atom.set(a, 4)
    t->expect(Array.length(queue))->Expect.toBe(1)
    flush()
    t->expect(seen)->Expect.toEqual([11, 23, 24])
  })

  test("the scheduler is only called once the outermost batch exits", t => {
    let (queue, _) = makeQueue()
    let a = Atom.make(1)
    EffectBase.make(
      ~scheduler=effect => Array.push(queue, effect),
      () => Atom.get(a)->ignore,
    )->ignore
    Batch.run(
      () => {
        Atom.set(a, 2)
        t->expect(Array.length(queue))->Expect.toBe(0)
      },
    )
    t->expect(Array.length(queue))->Expect.toBe(1)
  })

  test("run is a no-op for an effect that isn't due, or was disposed while waiting", t => {
    let (queue, flush) = makeQueue()
    let a = Atom.make(1)
    let runs = ref(0)
    let effect = EffectBase.make(
      ~scheduler=effect => Array.push(queue, effect),
      () => {
        runs := runs.contents + 1
        Atom.get(a)->ignore
      },
    )
    EffectBase.run(effect) // not due
    t->expect(runs.contents)->Expect.toBe(1)
    Atom.set(a, 2)
    EffectBase.dispose(effect)
    flush()
    t->expect(runs.contents)->Expect.toBe(1)
  })

  test("a change that is undone before it reruns still reruns it", t => {
    let (queue, flush) = makeQueue()
    let a = Atom.make(1)
    let seen = []
    EffectBase.make(
      ~scheduler=effect => Array.push(queue, effect),
      () => Array.push(seen, Atom.get(a)),
    )->ignore
    Atom.set(a, 2)
    Atom.set(a, 1)
    flush()
    t->expect(seen)->Expect.toEqual([1, 1])
  })
})

describe("EffectBase.Make(Scheduler.Microtask)", () => {
  module Effect = EffectBase.Make(Scheduler.Microtask)

  testAsync("reruns once, in a microtask, after any number of synchronous writes", async t => {
    let a = Atom.make(1)
    let seen = []
    let effect = Effect.make(() => Array.push(seen, Atom.get(a)))
    Atom.set(a, 2)
    Atom.set(a, 3)
    t->expect(seen)->Expect.toEqual([1])
    await Promise.resolve()
    t->expect(seen)->Expect.toEqual([1, 3])
    Atom.set(a, 4)
    Effect.dispose(effect)
    await Promise.resolve()
    t->expect(seen)->Expect.toEqual([1, 3])
  })
})

// White-box: how many consumers the atom's cell currently holds on to.
let consumerCount: Atom.t<'value, 'diff> => int = %raw(`atom => atom.cell.consumers.length`)

/** The message of whatever the function throws, or `None` if it returns normally. */
let messageThrownBy = (f: unit => unit): option<string> =>
  switch f() {
  | () => None
  | exception JsExn(error) => Some(error->JsExn.message->Option.getOr(""))
  }

describe("EffectBase.makeWithCleanup", () => {
  test("the cleanup runs before each rerun and on dispose, once each", t => {
    let a = Atom.make(1)
    let log = []
    let effect = Effect.makeWithCleanup(
      () => {
        let value = Atom.get(a)
        Array.push(log, `run ${Int.toString(value)}`)
        Some(() => Array.push(log, `cleanup ${Int.toString(value)}`))
      },
    )
    t->expect(log)->Expect.toEqual(["run 1"])
    Atom.set(a, 2)
    t->expect(log)->Expect.toEqual(["run 1", "cleanup 1", "run 2"])
    Effect.dispose(effect)
    t->expect(log)->Expect.toEqual(["run 1", "cleanup 1", "run 2", "cleanup 2"])
    Effect.dispose(effect) // already disposed: nothing left to clean up
    Atom.set(a, 3)
    t->expect(Array.length(log))->Expect.toBe(4)
  })

  test("the cleanup doesn't run when a rerun is skipped because nothing changed", t => {
    let a = Atom.make(1)
    let parity = Computed.make(() => mod(Atom.get(a), 2))
    let cleanups = ref(0)
    Effect.makeWithCleanup(
      () => {
        Signal.get(parity)->ignore
        Some(() => cleanups := cleanups.contents + 1)
      },
    )->ignore
    Atom.set(a, 3) // still odd
    t->expect(cleanups.contents)->Expect.toBe(0)
    Atom.set(a, 4)
    t->expect(cleanups.contents)->Expect.toBe(1)
  })

  test("a run that returns None has nothing to clean up, and clears the previous cleanup", t => {
    let a = Atom.make(1)
    let cleanups = ref(0)
    Effect.makeWithCleanup(
      () => Atom.get(a) === 1 ? Some(() => cleanups := cleanups.contents + 1) : None,
    )->ignore
    Atom.set(a, 2)
    Atom.set(a, 3)
    t->expect(cleanups.contents)->Expect.toBe(1)
  })

  test("signals read by the cleanup aren't tracked", t => {
    let a = Atom.make(1)
    let onlyReadInCleanup = Atom.make(0)
    let runs = ref(0)
    Effect.makeWithCleanup(
      () => {
        runs := runs.contents + 1
        Atom.get(a)->ignore
        Some(() => Atom.get(onlyReadInCleanup)->ignore)
      },
    )->ignore
    Atom.set(a, 2) // runs the cleanup, then the body
    t->expect(runs.contents)->Expect.toBe(2)
    Atom.set(onlyReadInCleanup, 1)
    t->expect(runs.contents)->Expect.toBe(2)
    t->expect(consumerCount(onlyReadInCleanup))->Expect.toBe(0)
  })

  test("an effect that disposes itself still gets that run's cleanup called", t => {
    let cleanups = ref(0)
    let self = ref(None)
    let a = Atom.make(1)
    self :=
      Some(
        Effect.makeWithCleanup(
          () => {
            if Atom.get(a) === 2 {
              self.contents->Option.forEach(Effect.dispose)
            }
            Some(() => cleanups := cleanups.contents + 1)
          },
        ),
      )
    Atom.set(a, 2) // cleans up run 1, then run 2 disposes itself
    t->expect(cleanups.contents)->Expect.toBe(2)
    t->expect(consumerCount(a))->Expect.toBe(0)
  })

  test("works with a scheduler passed as a value", t => {
    let a = Atom.make(1)
    let cleanups = ref(0)
    let effect = EffectBase.makeWithCleanup(
      ~scheduler=EffectBase.run,
      () => {
        Atom.get(a)->ignore
        Some(() => cleanups := cleanups.contents + 1)
      },
    )
    Atom.set(a, 2)
    EffectBase.dispose(effect)
    t->expect(cleanups.contents)->Expect.toBe(2)
  })
})

describe("EffectBase: effects created inside an effect", () => {
  test("are disposed when the outer effect reruns, rather than piling up", t => {
    let outer = Atom.make(1)
    let inner = Atom.make(10)
    let log = []
    Effect.make(
      () => {
        let outerValue = Atom.get(outer)
        Effect.make(() => Array.push(log, (outerValue, Atom.get(inner))))->ignore
      },
    )->ignore
    Atom.set(inner, 20)
    Atom.set(outer, 2)
    t->expect(consumerCount(inner))->Expect.toBe(1) // not one per outer run
    Atom.set(inner, 30)
    t->expect(log)->Expect.toEqual([(1, 10), (1, 20), (2, 20), (2, 30)])
  })

  test("are disposed, with their cleanups, when the outer effect is disposed", t => {
    let a = Atom.make(1)
    let log = []
    let outer = Effect.makeWithCleanup(
      () => {
        Effect.makeWithCleanup(
          () => {
            Atom.get(a)->ignore
            Some(() => Array.push(log, "inner cleanup"))
          },
        )->ignore
        Some(() => Array.push(log, "outer cleanup"))
      },
    )
    Effect.dispose(outer)
    t->expect(log)->Expect.toEqual(["inner cleanup", "outer cleanup"])
    t->expect(consumerCount(a))->Expect.toBe(0)
    Atom.set(a, 2)
    t->expect(Array.length(log))->Expect.toBe(2)
  })

  test("are still owned when created inside Untracked.run", t => {
    let outer = Atom.make(1)
    let inner = Atom.make(10)
    Effect.make(
      () => {
        Atom.get(outer)->ignore
        Untracked.run(() => Effect.make(() => Atom.get(inner)->ignore))->ignore
      },
    )->ignore
    Atom.set(outer, 2)
    Atom.set(outer, 3)
    t->expect(consumerCount(inner))->Expect.toBe(1)
  })

  test("an effect created by a cleanup isn't owned by the effect being cleaned up", t => {
    let a = Atom.make(1)
    let b = Atom.make(1)
    let created = []
    let outer = Effect.makeWithCleanup(
      () => {
        Atom.get(a)->ignore
        Some(() => Array.push(created, Effect.make(() => Atom.get(b)->ignore)))
      },
    )
    Atom.set(a, 2) // the cleanup creates one effect
    Effect.dispose(outer) // ...and another; neither is disposed along with `outer`
    t->expect(consumerCount(b))->Expect.toBe(2)
    created->Array.forEach(Effect.dispose)
    t->expect(consumerCount(b))->Expect.toBe(0)
  })
})

describe("EffectBase: errors", () => {
  test("an effect that throws on creation is disposed, and make throws", t => {
    let a = Atom.make(1)
    let thrown = messageThrownBy(
      () =>
        Effect.make(
          () => {
            Atom.get(a)->ignore
            JsError.throwWithMessage("boom")
          },
        )->ignore,
    )
    t->expect(thrown)->Expect.toEqual(Some("boom"))
    t->expect(consumerCount(a))->Expect.toBe(0)
  })

  test("with Scheduler.Sync, one effect throwing doesn't stop the others due from running", t => {
    let a = Atom.make(0)
    let seenBefore = []
    let seenAfter = []
    Effect.make(() => Array.push(seenBefore, Atom.get(a)))->ignore
    Effect.make(
      () =>
        if Atom.get(a) === 1 {
          JsError.throwWithMessage("boom")
        },
    )->ignore
    Effect.make(() => Array.push(seenAfter, Atom.get(a)))->ignore
    t->expect(messageThrownBy(() => Atom.set(a, 1)))->Expect.toEqual(Some("boom"))
    t->expect(Atom.get(a))->Expect.toBe(1) // the write itself landed
    t->expect(seenBefore)->Expect.toEqual([0, 1])
    t->expect(seenAfter)->Expect.toEqual([0, 1])
    // Nothing is left over to go wrong on the next write.
    t->expect(messageThrownBy(() => Atom.set(a, 2)))->Expect.toEqual(None)
    t->expect(seenAfter)->Expect.toEqual([0, 1, 2])
  })

  test("an effect that throws stays subscribed, and reruns on the next change", t => {
    let a = Atom.make(0)
    let seen = []
    Effect.make(
      () => {
        let value = Atom.get(a)
        if value === 1 {
          JsError.throwWithMessage("boom")
        }
        Array.push(seen, value)
      },
    )->ignore
    t->expect(messageThrownBy(() => Atom.set(a, 1)))->Expect.toEqual(Some("boom"))
    Atom.set(a, 2)
    t->expect(seen)->Expect.toEqual([0, 2])
  })

  test("when several effects throw, the first exception is the one rethrown", t => {
    let a = Atom.make(0)
    let throwOnOne = (message: string) =>
      Effect.make(
        () =>
          if Atom.get(a) === 1 {
            JsError.throwWithMessage(message)
          },
      )->ignore
    throwOnOne("first")
    throwOnOne("second")
    t->expect(messageThrownBy(() => Atom.set(a, 1)))->Expect.toEqual(Some("first"))
  })

  test("an exception from inside a batch surfaces when the outermost batch exits", t => {
    let a = Atom.make(0)
    Effect.make(
      () =>
        if Atom.get(a) === 1 {
          JsError.throwWithMessage("boom")
        },
    )->ignore
    let reachedEndOfBatch = ref(false)
    let thrown = messageThrownBy(
      () =>
        Batch.run(
          () => {
            Atom.set(a, 1)
            reachedEndOfBatch := true
          },
        ),
    )
    t->expect(reachedEndOfBatch.contents)->Expect.toBe(true)
    t->expect(thrown)->Expect.toEqual(Some("boom"))
  })

  test("a cleanup that throws doesn't stop the rest of a disposal", t => {
    let a = Atom.make(1)
    let innerCleanups = ref(0)
    let outer = Effect.makeWithCleanup(
      () => {
        Effect.makeWithCleanup(
          () => {
            Atom.get(a)->ignore
            Some(() => innerCleanups := innerCleanups.contents + 1)
          },
        )->ignore
        Effect.makeWithCleanup(() => Some(() => JsError.throwWithMessage("cleanup failed")))->ignore
        Some(() => JsError.throwWithMessage("outer cleanup failed"))
      },
    )
    // Children are disposed first, most recent first, so theirs is the first exception.
    t->expect(messageThrownBy(() => Effect.dispose(outer)))->Expect.toEqual(Some("cleanup failed"))
    t->expect(innerCleanups.contents)->Expect.toBe(1)
    t->expect(consumerCount(a))->Expect.toBe(0)
  })

  test("a rerun abandoned because its cleanup threw is attempted again on the next change", t => {
    let a = Atom.make(1)
    let runs = []
    Effect.makeWithCleanup(
      () => {
        let value = Atom.get(a)
        Array.push(runs, value)
        value === 1 ? Some(() => JsError.throwWithMessage("cleanup failed")) : None
      },
    )->ignore
    t->expect(messageThrownBy(() => Atom.set(a, 2)))->Expect.toEqual(Some("cleanup failed"))
    t->expect(runs)->Expect.toEqual([1])
    Atom.set(a, 3)
    t->expect(runs)->Expect.toEqual([1, 3])
  })
})

describe("EffectBase: effects that never settle", () => {
  let gaveUp = (thrown: option<string>): bool =>
    switch thrown {
    | Some(message) => String.includes(message, "still triggering each other")
    | None => false
    }

  test(
    "with Scheduler.Sync, an effect that keeps writing what it reads throws instead of hanging",
    t => {
      let a = Atom.make(0)
      let runs = ref(0)
      let thrown = messageThrownBy(
        () =>
          Effect.make(
            () => {
              runs := runs.contents + 1
              Atom.set(a, Atom.get(a) + 1)
            },
          )->ignore,
      )
      t->expect(gaveUp(thrown))->Expect.toBe(true)
      t->expect(runs.contents < 200)->Expect.toBe(true)
      // It threw out of its own first run, so it was disposed.
      t->expect(consumerCount(a))->Expect.toBe(0)
    },
  )

  test("two effects that keep triggering each other throw, and can settle again afterwards", t => {
    let enabled = Atom.make(false)
    let ping = Atom.make(0)
    let pong = Atom.make(0)
    Effect.make(
      () => {
        let value = Atom.get(ping)
        if Atom.get(enabled) {
          Atom.set(pong, value + 1)
        }
      },
    )->ignore
    Effect.make(
      () => {
        let value = Atom.get(pong)
        if Atom.get(enabled) {
          Atom.set(ping, value + 1)
        }
      },
    )->ignore
    t->expect(gaveUp(messageThrownBy(() => Atom.set(enabled, true))))->Expect.toBe(true)
    // Whatever was still due runs after the next write -- which, here, stops the loop.
    t->expect(messageThrownBy(() => Atom.set(enabled, false)))->Expect.toEqual(None)
    let pongBefore = Atom.get(pong)
    t->expect(messageThrownBy(() => Atom.set(ping, -1)))->Expect.toEqual(None)
    t->expect(Atom.get(pong))->Expect.toBe(pongBefore)
  })

  test("a long but finite chain of effects triggering each other is fine", t => {
    let atoms = Array.fromInitializer(~length=60, _ => Atom.make(0))
    for i in 0 to Array.length(atoms) - 2 {
      Effect.make(
        () => Atom.set(Array.getUnsafe(atoms, i + 1), Atom.get(Array.getUnsafe(atoms, i))),
      )->ignore
    }
    Atom.set(Array.getUnsafe(atoms, 0), 7)
    t->expect(Atom.get(Array.getUnsafe(atoms, Array.length(atoms) - 1)))->Expect.toBe(7)
  })
})

describe("EffectBase.Make(Scheduler.Microtask): one shared microtask", () => {
  module Effect = EffectBase.Make(Scheduler.Microtask)

  // Stands in for the host's microtask queue, so a test can see how many microtasks were queued,
  // run them when it chooses, and catch what they throw (which would otherwise be an uncaught
  // exception). Returns the queued tasks, and a function that puts the real one back.
  let installFakeMicrotasks: unit => (array<unit => unit>, unit => unit) = %raw(`() => {
    const original = globalThis.queueMicrotask;
    const tasks = [];
    globalThis.queueMicrotask = task => { tasks.push(task); };
    return [tasks, () => { globalThis.queueMicrotask = original; }];
  }`)

  // Runs the function with the fake queue in place, handing it the queued tasks.
  let withFakeMicrotasks = (f: array<unit => unit> => unit): unit => {
    let (tasks, restore) = installFakeMicrotasks()
    switch f(tasks) {
    | () => restore()
    | exception error =>
      restore()
      throw(error)
    }
  }

  // Runs every queued task, including ones queued meanwhile; returns what they threw.
  let drain = (tasks: array<unit => unit>): array<string> => {
    let thrown = []
    while Array.length(tasks) > 0 {
      switch Array.shift(tasks) {
      | Some(task) =>
        switch task() {
        | () => ()
        | exception JsExn(error) => Array.push(thrown, error->JsExn.message->Option.getOr(""))
        }
      | None => ()
      }
    }
    thrown
  }

  test("every effect due shares one microtask, and runs in the order it became due", t =>
    withFakeMicrotasks(
      tasks => {
        let a = Atom.make(1)
        let b = Atom.make(1)
        let order = []
        Effect.make(() => Array.push(order, `first:${Int.toString(Atom.get(a))}`))->ignore
        Effect.make(() => Array.push(order, `second:${Int.toString(Atom.get(b))}`))->ignore
        Effect.make(() => Array.push(order, `third:${Int.toString(Atom.get(a))}`))->ignore
        Atom.set(b, 2)
        Atom.set(a, 2)
        Atom.set(b, 3)
        t->expect(Array.length(tasks))->Expect.toBe(1)
        t->expect(drain(tasks))->Expect.toEqual([])
        t
        ->expect(order)
        ->Expect.toEqual(["first:1", "second:1", "third:1", "second:3", "first:2", "third:2"])
        // The next change needs a microtask of its own again.
        Atom.set(a, 3)
        t->expect(Array.length(tasks))->Expect.toBe(1)
        drain(tasks)->ignore
      },
    )
  )

  test("effects made due by an effect run in the same microtask", t =>
    withFakeMicrotasks(
      tasks => {
        let a = Atom.make(1)
        let b = Atom.make(0)
        let seen = []
        Effect.make(() => Atom.set(b, Atom.get(a) * 10))->ignore
        Effect.make(() => Array.push(seen, Atom.get(b)))->ignore
        Atom.set(a, 2)
        t->expect(Array.length(tasks))->Expect.toBe(1)
        Array.shift(tasks)->Option.forEach(flush => flush())
        t->expect(seen)->Expect.toEqual([10, 20])
        t->expect(Array.length(tasks))->Expect.toBe(0)
      },
    )
  )

  test("one effect throwing doesn't stop the others, and every exception is reported", t =>
    withFakeMicrotasks(
      tasks => {
        let a = Atom.make(0)
        let seen = []
        let throwOnOne = (message: string) =>
          Effect.make(
            () =>
              if Atom.get(a) === 1 {
                JsError.throwWithMessage(message)
              },
          )->ignore
        throwOnOne("first")
        Effect.make(() => Array.push(seen, Atom.get(a)))->ignore
        throwOnOne("second")
        t->expect(messageThrownBy(() => Atom.set(a, 1)))->Expect.toEqual(None) // not from the write
        t->expect(drain(tasks))->Expect.toEqual(["first", "second"])
        t->expect(seen)->Expect.toEqual([0, 1])
        // And the scheduler still works afterwards.
        Atom.set(a, 2)
        t->expect(drain(tasks))->Expect.toEqual([])
        t->expect(seen)->Expect.toEqual([0, 1, 2])
      },
    )
  )

  test("effects that never settle are stopped, with an error, instead of running forever", t =>
    withFakeMicrotasks(
      tasks => {
        let enabled = Atom.make(false)
        let counter = Atom.make(0)
        let runs = ref(0)
        Effect.make(
          () => {
            runs := runs.contents + 1
            let value = Atom.get(counter)
            if Atom.get(enabled) {
              Atom.set(counter, value + 1)
            }
          },
        )->ignore
        Atom.set(enabled, true)
        let thrown = drain(tasks)
        t->expect(Array.length(thrown))->Expect.toBe(1)
        t
        ->expect(String.includes(Array.getUnsafe(thrown, 0), "still triggering each other"))
        ->Expect.toBe(true)
        t->expect(runs.contents < 200)->Expect.toBe(true)

        // It's still due, and reruns the next time anything is scheduled -- here, with the loop
        // switched off by then, to completion.
        let other = Atom.make(0)
        Effect.make(() => Atom.get(other)->ignore)->ignore
        Atom.set(enabled, false)
        t->expect(Array.length(tasks))->Expect.toBe(0) // already due: not scheduled again
        let runsBefore = runs.contents
        Atom.set(other, 1)
        t->expect(drain(tasks))->Expect.toEqual([])
        t->expect(runs.contents)->Expect.toBe(runsBefore + 1)
      },
    )
  )
})

describe("Untracked.run", () => {
  test("reading a signal inside it does not establish a dependency", t => {
    let a = Atom.make(1)
    let runs = ref(0)
    Effect.make(
      () => {
        runs := runs.contents + 1
        Untracked.run(() => Atom.get(a))->ignore
      },
    )->ignore
    t->expect(runs.contents)->Expect.toBe(1)
    Atom.set(a, 2)
    t->expect(runs.contents)->Expect.toBe(1)
  })
})
