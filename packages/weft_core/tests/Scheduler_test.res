open Vitest

module Default = Scheduler.Default

let wait = ms => Promise.make((resolve, _) => setTimeout(() => resolve(), ms)->ignore)

describe("Scheduler.Default", () => {
  testAsync("runs tasks later, most urgent first, skipping cancelled ones", async t => {
    let ran = []
    let _ = Default.scheduleCallback(Low, () => ran->Array.push("low"))
    let _ = Default.scheduleCallback(Normal, () => ran->Array.push("normal"))
    let cancelled = Default.scheduleCallback(UserBlocking, () => ran->Array.push("cancelled"))
    let _ = Default.scheduleCallback(UserBlocking, () => ran->Array.push("user-blocking"))
    Default.cancelCallback(cancelled)
    t->expect(ran)->Expect.toEqual([])
    await wait(20)
    t->expect(ran)->Expect.toEqual(["user-blocking", "normal", "low"])
  })

  testAsync("yields once a slice has run for 5 ms", async t => {
    let slices = []
    let busyUntilYield = () => {
      let start = Default.now()
      while !Default.shouldYield() {
        ()
      }
      slices->Array.push(Default.now() -. start)
    }
    let _ = Default.scheduleCallback(Normal, busyUntilYield)
    let _ = Default.scheduleCallback(Normal, () => slices->Array.push(-1.0))
    await wait(30)
    // The first task ran until its slice was used up, and the queue carried on afterwards.
    t->expect(Array.length(slices))->Expect.toBe(2)
    t->expect(slices->Array.getUnsafe(0) >= 4.0)->Expect.toBe(true)
  })
})
