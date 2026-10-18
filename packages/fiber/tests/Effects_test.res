@@jsxConfig({version: 4, module_: "TestJsx"})

open Vitest

/** What happened, in order. */
module Log = {
  let entries: array<string> = []
  let add = entry => entries->Array.push(entry)
  let clear = () => entries->Array.splice(~start=0, ~remove=Array.length(entries), ~insert=[])
}

/** What happened since the last `take` (or `Log.clear`). */
let take = () => {
  let entries = Log.entries->Array.copy
  Log.clear()
  entries
}

/** Logs its renders and each kind of effect, mounting and cleaning up. `dep` drives the deps. */
module Logger = {
  @jsx.component
  let make = (~name: string, ~dep: int=0, ~children: TestJsx.element=TestJsx.null) => {
    Log.add(`render ${name}`)
    Hooks.useLayoutEffect1(() => {
      Log.add(`layout ${name} ${Int.toString(dep)}`)
      Some(() => Log.add(`layout cleanup ${name} ${Int.toString(dep)}`))
    }, [dep])
    Hooks.useEffect1(() => {
      Log.add(`effect ${name} ${Int.toString(dep)}`)
      Some(() => Log.add(`cleanup ${name} ${Int.toString(dep)}`))
    }, [dep])
    <div id=name> children </div>
  }
}

let wait = () => Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)

describe("useEffect and useLayoutEffect", () => {
  test("run after rendering, children before parents, layout before passive", t => {
    Log.clear()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Logger name="parent">
        <Logger name="child" />
      </Logger>,
    )
    t
    ->expect(take())
    ->Expect.toEqual([
      "render parent",
      "render child",
      "layout child 0",
      "layout parent 0",
      "effect child 0",
      "effect parent 0",
    ])
  })

  testAsync("layout effects run in the commit, passive ones after it", async t => {
    Log.clear()
    let renderer = TestRenderer.create()
    TestRenderer.flushSync(() => TestRenderer.scheduleRender(renderer, <Logger name="a" />))
    t->expect(take())->Expect.toEqual(["render a", "layout a 0"])
    await wait()
    t->expect(take())->Expect.toEqual(["effect a 0"])
  })

  test("rerun when deps change, every cleanup before any effect", t => {
    Log.clear()
    let renderer = TestRenderer.create()
    let view = dep => <>
      <Logger name="a" dep />
      <Logger name="b" dep />
    </>
    TestRenderer.render(renderer, view(0))
    Log.clear()
    TestRenderer.render(renderer, view(1))
    t
    ->expect(take())
    ->Expect.toEqual([
      "render a",
      "render b",
      "layout cleanup a 0",
      "layout cleanup b 0",
      "layout a 1",
      "layout b 1",
      "cleanup a 0",
      "cleanup b 0",
      "effect a 1",
      "effect b 1",
    ])
  })

  test("don't rerun while deps are unchanged", t => {
    Log.clear()
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Logger name="a" dep=1 />)
    Log.clear()
    TestRenderer.render(renderer, <Logger name="a" dep=1 />)
    t->expect(take())->Expect.toEqual(["render a"])
  })

  test("clean up when the component is removed", t => {
    Log.clear()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Logger name="parent">
        <Logger name="child" />
      </Logger>,
    )
    Log.clear()
    TestRenderer.render(renderer, TestJsx.null)
    t
    ->expect(take())
    ->Expect.toEqual([
      "layout cleanup parent 0",
      "layout cleanup child 0",
      "cleanup parent 0",
      "cleanup child 0",
    ])
  })

  test("unmount cleans up everything", t => {
    Log.clear()
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Logger name="a" />)
    Log.clear()
    TestRenderer.unmount(renderer)
    t->expect(take())->Expect.toEqual(["layout cleanup a 0", "cleanup a 0"])
  })

  test("the variants without deps run every commit, the 0 variants once", t => {
    let runs = ref(0)
    let onceRuns = ref(0)
    module Every = {
      @jsx.component
      let make = (~n: int) => {
        Hooks.useEffect(
          () => {
            runs := runs.contents + 1
            None
          },
        )
        Hooks.useEffect0(
          () => {
            onceRuns := onceRuns.contents + 1
            None
          },
        )
        TestJsx.int(n)
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Every n=1 />)
    TestRenderer.render(renderer, <Every n=2 />)
    TestRenderer.render(renderer, <Every n=3 />)
    t->expect((runs.contents, onceRuns.contents))->Expect.toEqual((3, 1))
  })

  test("an update in a layout effect renders before the commit returns", t => {
    module Measure = {
      @jsx.component
      let make = () => {
        let (width, setWidth) = Hooks.useState(() => 0)
        Hooks.useLayoutEffect0(
          () => {
            setWidth(_ => 42)
            None
          },
        )
        <span id="w"> {TestJsx.int(width)} </span>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.flushSync(() => TestRenderer.scheduleRender(renderer, <Measure />))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="w">42</span>`)
  })

  test("an update in an effect renders, inside act", t => {
    module Load = {
      @jsx.component
      let make = () => {
        let (data, setData) = Hooks.useState(() => "loading")
        Hooks.useEffect0(
          () => {
            setData(_ => "loaded")
            None
          },
        )
        <span id="d"> {TestJsx.string(data)} </span>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Load />)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="d">loaded</span>`)
  })

  test("an effect that throws doesn't stop the others, and its error comes out", t => {
    Log.clear()
    module Throws = {
      @jsx.component
      let make = () => {
        Hooks.useEffect0(() => JsError.throwWithMessage("effect failed"))
        TestJsx.null
      }
    }
    let renderer = TestRenderer.create()
    t
    ->expect(
      () =>
        TestRenderer.render(
          renderer,
          <>
            <Throws />
            <Logger name="after" />
          </>,
        ),
    )
    ->Expect.toThrow(~message="effect failed")
    t->expect(take()->Array.includes("effect after 0"))->Expect.toBe(true)
  })

  test("an effect updating state forever throws", t => {
    module Loop = {
      @jsx.component
      let make = () => {
        let (n, setN) = Hooks.useState(() => 0)
        Hooks.useLayoutEffect1(
          () => {
            setN(n => n + 1)
            None
          },
          [n],
        )
        TestJsx.null
      }
    }
    t
    ->expect(() => TestRenderer.render(TestRenderer.create(), <Loop />))
    ->Expect.toThrow(~message="maximum update depth exceeded")
  })
})

describe("Refs", () => {
  module WithRef = {
    @jsx.component
    let make = (~box: Ref.t<Nullable.t<TestJsx.node>>, ~seen: ref<string>) => {
      Hooks.useLayoutEffect0(() => {
        seen :=
          switch Nullable.toOption(box.current) {
          | Some(node) => TestRenderer.tag(node)
          | None => "nothing"
          }
        None
      })
      <section id="target" ref=box />
    }
  }

  test("a host ref holds the node, before layout effects run, until it's removed", t => {
    let box: Ref.t<Nullable.t<TestJsx.node>> = {current: Nullable.null}
    let seen = ref("")
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <WithRef box seen />)
    t->expect(seen.contents)->Expect.toBe("section")
    let target = TestRenderer.findById(renderer, "target")->Option.getUnsafe
    t->expect(box.current)->Expect.toEqual(Nullable.make(target))
    TestRenderer.render(renderer, TestJsx.null)
    t->expect(box.current)->Expect.toEqual(Nullable.null)
  })

  test("moving to another ref clears the old one", t => {
    let first: Ref.t<Nullable.t<TestJsx.node>> = {current: Nullable.null}
    let second: Ref.t<Nullable.t<TestJsx.node>> = {current: Nullable.null}
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <div id="a" ref=first />)
    TestRenderer.render(renderer, <div id="a" ref=second />)
    t->expect(Nullable.isNullable(first.current))->Expect.toBe(true)
    t->expect(second.current->Nullable.toOption->Option.map(TestRenderer.uid))->Expect.toBe(Some(0))
  })
})

describe("useSyncExternalStore", () => {
  module Store = {
    let value = ref(0)
    let listeners: array<unit => unit> = []
    let subscribe = listener => {
      listeners->Array.push(listener)
      () =>
        listeners->Array.splice(~start=listeners->Array.indexOf(listener), ~remove=1, ~insert=[])
    }
    let getSnapshot = () => value.contents
    let set = next => {
      value := next
      listeners->Array.forEach(listener => listener())
    }
  }

  module Reader = {
    @jsx.component
    let make = () => {
      let value = Hooks.useSyncExternalStore(
        ~subscribe=Store.subscribe,
        ~getSnapshot=Store.getSnapshot,
      )
      <span id="v"> {TestJsx.int(value)} </span>
    }
  }

  test("renders the snapshot, follows changes, and unsubscribes on removal", t => {
    Store.value := 1
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Reader />)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="v">1</span>`)
    t->expect(Array.length(Store.listeners))->Expect.toBe(1)
    TestRenderer.act(() => Store.set(2))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="v">2</span>`)
    TestRenderer.render(renderer, TestJsx.null)
    t->expect(Array.length(Store.listeners))->Expect.toBe(0)
  })

  test("a change between rendering and subscribing is caught", t => {
    module Racy = {
      @jsx.component
      let make = () => {
        let value = Hooks.useSyncExternalStore(
          ~subscribe=Store.subscribe,
          ~getSnapshot=Store.getSnapshot,
        )
        // Changes the store after rendering, before the subscription exists.
        Hooks.useLayoutEffect0(
          () => {
            if Store.value.contents == 10 {
              Store.value := 11
            }
            None
          },
        )
        <span id="v"> {TestJsx.int(value)} </span>
      }
    }
    Store.value := 10
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Racy />)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="v">11</span>`)
    TestRenderer.unmount(renderer)
  })
})

describe("useSyncExternalStore: more cases", () => {
  module Quiet = {
    let value = ref(0)
    let subscribe = _ => () => ()
    let getSnapshot = () => value.contents
  }

  test("a change after the commit but before subscribing is caught", t => {
    module Changer = {
      @jsx.component
      let make = () => {
        // An earlier sibling's effect runs before the reader subscribes.
        Hooks.useEffect0(
          () => {
            Quiet.value := 5
            None
          },
        )
        TestJsx.null
      }
    }
    module Reader = {
      @jsx.component
      let make = () =>
        <i id="value">
          {TestJsx.int(
            Hooks.useSyncExternalStore(~subscribe=Quiet.subscribe, ~getSnapshot=Quiet.getSnapshot),
          )}
        </i>
    }
    Quiet.value := 0
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <>
        <Changer />
        <Reader />
      </>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="value">5</i>`)
  })

  test("a change during the commit is caught before the commit returns", t => {
    module ChangesInLayout = {
      @jsx.component
      let make = () => {
        // A child's layout effect runs before its parent's.
        Hooks.useLayoutEffect0(
          () => {
            Quiet.value := 7
            None
          },
        )
        TestJsx.null
      }
    }
    module Reader = {
      @jsx.component
      let make = (~children: TestJsx.element) => {
        let value = Hooks.useSyncExternalStore(
          ~subscribe=Quiet.subscribe,
          ~getSnapshot=Quiet.getSnapshot,
        )
        <i id="value">
          {TestJsx.int(value)}
          children
        </i>
      }
    }
    Quiet.value := 0
    let renderer = TestRenderer.create()
    // No `act`: passive effects don't run, so only the layout-time check can catch it.
    TestRenderer.flushSync(
      () =>
        TestRenderer.scheduleRender(
          renderer,
          <Reader>
            <ChangesInLayout />
          </Reader>,
        ),
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="value">7</i>`)
  })
})
