@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

open Vitest

module Atom = Signals.Atom
module Batch = Signals.Batch
module TestJsx = WeftCore.TestJsx
module TestRenderer = WeftCore.TestRenderer

let renders = ref(0)

let textOf = renderer => TestRenderer.toString(renderer)

describe("useAtom", () => {
  test("renders the atom's value and follows writes from anywhere", t => {
    let count = Atom.make(1)
    module Count = {
      @jsx.component
      let make = () => {
        let (value, update) = SignalHooks.useAtom(count)
        <button id="count" onClick={() => update(n => n + 1)}> {TestJsx.int(value)} </button>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Count />)
    t->expect(textOf(renderer))->Expect.toBe(`<button id="count">1</button>`)
    TestRenderer.click(renderer, "count")
    t
    ->expect((Atom.peek(count), textOf(renderer)))
    ->Expect.toEqual((2, `<button id="count">2</button>`))
    TestRenderer.act(() => Atom.set(count, 10))
    t->expect(textOf(renderer))->Expect.toBe(`<button id="count">10</button>`)
  })

  test("writes in one batch render once", t => {
    let a = Atom.make(0)
    let b = Atom.make(0)
    module Sum = {
      @jsx.component
      let make = () => {
        renders := renders.contents + 1
        let (x, _) = SignalHooks.useAtom(a)
        let (y, _) = SignalHooks.useAtom(b)
        TestJsx.int(x + y)
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Sum />)
    renders := 0
    TestRenderer.act(
      () =>
        Batch.run(
          () => {
            Atom.set(a, 1)
            Atom.set(b, 2)
          },
        ),
    )
    t->expect((textOf(renderer), renders.contents))->Expect.toEqual(("3", 1))
  })

  test("unsubscribes once removed", t => {
    let count = Atom.make(0)
    // Lazy: it only recomputes while something subscribed reads it.
    let computations = ref(0)
    let doubled = Signals.Computed.make(
      () => {
        computations := computations.contents + 1
        Atom.get(count) * 2
      },
    )
    module Doubled = {
      @jsx.component
      let make = () => TestJsx.int(SignalHooks.useSignal(doubled))
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Doubled />)
    TestRenderer.act(() => Atom.set(count, 1))
    t->expect(textOf(renderer))->Expect.toBe("2")
    TestRenderer.render(renderer, TestJsx.null)
    let before = computations.contents
    TestRenderer.act(() => Atom.set(count, 2))
    t->expect(computations.contents)->Expect.toBe(before)
  })
})

describe("useSignal and useComputed", () => {
  test("a computed renders again only when its value changes", t => {
    let count = Atom.make(1)
    let parity = Signals.Computed.make(() => mod(Atom.get(count), 2) == 0 ? "even" : "odd")
    module Parity = {
      @jsx.component
      let make = () => {
        renders := renders.contents + 1
        TestJsx.string(SignalHooks.useSignal(parity))
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Parity />)
    renders := 0
    TestRenderer.act(() => Atom.set(count, 3))
    t->expect((textOf(renderer), renders.contents))->Expect.toEqual(("odd", 0))
    TestRenderer.act(() => Atom.set(count, 4))
    t->expect((textOf(renderer), renders.contents))->Expect.toEqual(("even", 1))
  })

  test("useComputed1 derives from signals and props, remade when deps change", t => {
    let price = Atom.make(10)
    module Total = {
      @jsx.component
      let make = (~quantity: int) => {
        let total = SignalHooks.useComputed1(() => Atom.get(price) * quantity, [quantity])
        TestJsx.int(total)
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Total quantity=2 />)
    t->expect(textOf(renderer))->Expect.toBe("20")
    TestRenderer.act(() => Atom.set(price, 11))
    t->expect(textOf(renderer))->Expect.toBe("22")
    TestRenderer.render(renderer, <Total quantity=3 />)
    t->expect(textOf(renderer))->Expect.toBe("33")
    TestRenderer.act(() => Atom.set(price, 1))
    t->expect(textOf(renderer))->Expect.toBe("3")
  })

  test("useComputed0 keeps one computed for the component's lifetime", t => {
    let name = Atom.make("ada")
    let computations = ref(0)
    module Shout = {
      @jsx.component
      let make = (~suffix: string) => {
        let loud = SignalHooks.useComputed0(
          () => {
            computations := computations.contents + 1
            String.toUpperCase(Atom.get(name))
          },
        )
        TestJsx.string(loud ++ suffix)
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Shout suffix="!" />)
    TestRenderer.render(renderer, <Shout suffix="?" />)
    t->expect((textOf(renderer), computations.contents))->Expect.toEqual(("ADA?", 1))
    TestRenderer.act(() => Atom.set(name, "grace"))
    t->expect(textOf(renderer))->Expect.toBe("GRACE?")
  })

  test("an atom changed while a transition is paused doesn't commit mixed values", t => {
    let value = Atom.make(1)
    module Reader = {
      @jsx.component
      let make = (~id: string) => {
        let (current, _) = SignalHooks.useAtom(value)
        WeftCore.TestScheduler.advanceTime(3.0)
        <i id> {TestJsx.int(current)} </i>
      }
    }
    let renderer = TestRenderer.create()
    WeftCore.Transition.start(
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
    WeftCore.TestScheduler.flushTask()->ignore
    Atom.set(value, 2)
    WeftCore.TestScheduler.flushAll()
    t
    ->expect(textOf(renderer))
    ->Expect.toBe(`<i id="r1">2</i><i id="r2">2</i><i id="r3">2</i>`)
  })
})
