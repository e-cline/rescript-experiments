module Sync = {
  // No queue of its own: `Node.settle` already hands effects over one at a time, in the order
  // they became due, and never re-entrantly.
  let schedule = EffectBase.run
}

module Microtask = {
  @val external queueMicrotask: (unit => unit) => unit = "queueMicrotask"

  /** Effects due to rerun in the next (or the current) `flush`, in the order they became due. */
  let queue: array<EffectBase.t> = []

  /**
  Whether a `flush` is already on its way (queued as a microtask, or running), so `schedule` has
  no need to queue another.
  */
  let isScheduled = ref(false)

  /** The counterpart of `Node.maxSettlePasses`, for effects triggering each other from here. */
  let maxPasses = 100

  /** Rethrows an exception where the host will report it as uncaught, without interrupting us. */
  let report = (error: exn): unit => queueMicrotask(() => throw(error))

  let flush = (): unit => {
    let errors: array<exn> = []
    let index = ref(0)
    let pass = ref(1)
    // Where the effects that were already due when the current pass started end. Effects that
    // become due while this runs join the same queue (`isScheduled` is still set), and so the
    // same microtask -- which is what lets this count the passes.
    let passEnd = ref(Array.length(queue))
    while index.contents < Array.length(queue) && pass.contents <= maxPasses {
      if index.contents === passEnd.contents {
        pass := pass.contents + 1
        passEnd := Array.length(queue)
      } else {
        let effect = Array.getUnsafe(queue, index.contents)
        index := index.contents + 1
        switch EffectBase.run(effect) {
        | () => ()
        | exception error => Array.push(errors, error)
        }
      }
    }
    // Everything, unless it gave up: then whatever is still due stays queued.
    let gaveUp = index.contents < Array.length(queue)
    Array.splice(queue, ~start=0, ~remove=index.contents, ~insert=[])
    isScheduled := false
    errors->Array.forEach(report)
    if gaveUp {
      queueMicrotask(() =>
        JsError.throwWithMessage(
          `Effects were still triggering each other after ${Int.toString(
              maxPasses,
            )} passes: an effect is probably writing a signal that it, or an effect it triggers, reads, without ever settling. The effects still due will rerun the next time an effect is scheduled.`,
        )
      )
    }
  }

  let schedule = (effect: EffectBase.t): unit => {
    Array.push(queue, effect)
    if !isScheduled.contents {
      isScheduled := true
      queueMicrotask(flush)
    }
  }
}
