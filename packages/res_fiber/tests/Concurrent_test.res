@@jsxConfig({version: 4, module_: "TestJsx"})

/***
Transitions on `TestScheduler`: components advance its clock as they render, so a transition's
render yields after a few of them, and a test can look at (or interrupt) a render that's partway.
*/

open Vitest

module Log = {
  let entries: array<string> = []
  let add = entry => entries->Array.push(entry)
  let clear = () => entries->Array.splice(~start=0, ~remove=Array.length(entries), ~insert=[])
  let take = () => {
    let taken = entries->Array.copy
    clear()
    taken
  }
}

/** Takes 2 ms to render, so three of them use up a 5 ms slice. */
module Slow = {
  @jsx.component
  let make = (~name: string, ~text: string) => {
    Log.add(name)
    TestScheduler.advanceTime(2.0)
    <li id=name> {TestJsx.string(text)} </li>
  }
}

let setText: ref<(string => string) => unit> = ref(_ => ())
let setCount: ref<(int => int) => unit> = ref(_ => ())

module App = {
  @jsx.component
  let make = () => {
    let (text, set) = Hooks.useState(() => "a")
    let (count, setC) = Hooks.useState(() => 0)
    setText := set
    setCount := setC
    Log.add("App")
    <ul id="list" title={Int.toString(count)}>
      <Slow name="one" text />
      <Slow name="two" text />
      <Slow name="three" text />
      <Slow name="four" text />
    </ul>
  }
}

let shows = (text, ~count=0) =>
  `<ul id="list" title="${Int.toString(count)}">${["one", "two", "three", "four"]
    ->Array.map(name => `<li id="${name}">${text}</li>`)
    ->Array.join("")}</ul>`

let mountApp = () => {
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, <App />)
  Log.clear()
  renderer
}

describe("Transitions", () => {
  test("render in slices, keeping the old screen until they finish", t => {
    let renderer = mountApp()
    Transition.start(() => setText.contents(_ => "b"))
    t->expect(TestScheduler.hasPendingTasks())->Expect.toBe(true)
    TestScheduler.flushTask()->ignore
    t->expect(Log.take())->Expect.toEqual(["App", "one", "two", "three"])
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(shows("a"))
    TestScheduler.flushAll()
    // The render continued where it stopped.
    t->expect(Log.take())->Expect.toEqual(["four"])
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(shows("b"))
  })

  test("a sync update interrupts a transition, which then starts again", t => {
    let renderer = mountApp()
    Transition.start(() => setText.contents(_ => "b"))
    TestScheduler.flushTask()->ignore
    Log.clear()
    TestRenderer.flushSync(() => setCount.contents(c => c + 1))
    // The sync render skips the transition's update.
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(shows("a", ~count=1))
    t->expect(Log.take())->Expect.toEqual(["App", "one", "two", "three", "four"])
    TestScheduler.flushAll()
    t->expect(Log.take())->Expect.toEqual(["App", "one", "two", "three", "four"])
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(shows("b", ~count=1))
  })

  testAsync("a default update interrupts a transition too", async t => {
    let renderer = mountApp()
    Transition.start(() => setText.contents(_ => "b"))
    TestScheduler.flushTask()->ignore
    setCount.contents(c => c + 1)
    await Promise.resolve()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(shows("a", ~count=1))
    TestScheduler.flushAll()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(shows("b", ~count=1))
  })

  test("skipped updates are applied later, in their original order", t => {
    let setLetters = ref(_ => ())
    module Letters = {
      @jsx.component
      let make = () => {
        let (letters, set) = Hooks.useState(() => "")
        setLetters := set
        <span id="letters"> {TestJsx.string(letters)} </span>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Letters />)
    Transition.start(() => setLetters.contents(s => s ++ "A"))
    TestRenderer.flushSync(() => setLetters.contents(s => s ++ "B"))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="letters">B</span>`)
    Transition.start(() => setLetters.contents(s => s ++ "C"))
    TestScheduler.flushAll()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="letters">ABC</span>`)
  })

  test("unmounting during a paused render throws it away", t => {
    let renderer = mountApp()
    Transition.start(() => setText.contents(_ => "b"))
    TestScheduler.flushTask()->ignore
    TestRenderer.unmount(renderer)
    TestScheduler.flushAll()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("")
  })
})

describe("useTransition and useDeferredValue", () => {
  test("useTransition is pending until the transition commits", t => {
    let start = ref(_ => ())
    let setQuery = ref(_ => ())
    module Search = {
      @jsx.component
      let make = () => {
        let (isPending, startTransition) = Hooks.useTransition()
        let (query, set) = Hooks.useState(() => "")
        start := startTransition
        setQuery := set
        <p id="p"> {TestJsx.string(isPending ? `pending ${query}` : `showing ${query}`)} </p>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Search />)
    let firstStart = start.contents
    TestRenderer.flushSync(() => start.contents(() => setQuery.contents(_ => "x")))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<p id="p">pending </p>`)
    TestScheduler.flushAll()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<p id="p">showing x</p>`)
    t->expect(start.contents === firstStart)->Expect.toBe(true)
  })

  test("useDeferredValue lags an urgent update by one transition", t => {
    let setText = ref(_ => ())
    module Deferred = {
      @jsx.component
      let make = () => {
        let (text, set) = Hooks.useState(() => "")
        setText := set
        let deferred = Hooks.useDeferredValue(text)
        <p id="d"> {TestJsx.string(`${text}|${deferred}`)} </p>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Deferred />)
    TestRenderer.flushSync(() => setText.contents(_ => "x"))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<p id="d">x|</p>`)
    TestScheduler.flushAll()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<p id="d">x|x</p>`)
  })
})

describe("useSyncExternalStore in a paused render", () => {
  module Store = {
    let value = ref(1)
    let subscribe = _ => () => ()
    let getSnapshot = () => value.contents
  }

  module Reader = {
    @jsx.component
    let make = (~id: string) => {
      let value = Hooks.useSyncExternalStore(
        ~subscribe=Store.subscribe,
        ~getSnapshot=Store.getSnapshot,
      )
      TestScheduler.advanceTime(3.0)
      <i id> {TestJsx.int(value)} </i>
    }
  }

  test("a store change while it's paused doesn't commit a mix of values", t => {
    Store.value := 1
    let renderer = TestRenderer.create()
    Transition.start(
      () =>
        TestRenderer.scheduleRender(
          renderer,
          <>
            <Reader id="r1" />
            <Reader id="r2" />
            <Reader id="r3" />
          </>,
        ),
    )
    TestScheduler.flushTask()->ignore
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("")
    // Changed without telling anyone: nothing is subscribed yet.
    Store.value := 2
    TestScheduler.flushAll()
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<i id="r1">2</i><i id="r2">2</i><i id="r3">2</i>`)
  })
})
