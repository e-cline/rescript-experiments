@@jsxConfig({version: 4, module_: "TestJsx"})

open Vitest

let rendered = (element: TestJsx.element) => {
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, element)
  renderer
}

let textOf = (renderer, id) =>
  switch TestRenderer.findById(renderer, id) {
  | Some(node) => TestRenderer.children(node)->Array.map(TestRenderer.text)->Array.join("")
  | None => failwith(`no #${id}`)
  }

/** Counts calls by name, so tests can see which components rendered. */
module Renders = {
  let counts: dict<int> = Dict.make()
  let record = name => counts->Dict.set(name, counts->Dict.get(name)->Option.getOr(0) + 1)
  let get = name => counts->Dict.get(name)->Option.getOr(0)
  let reset = () => counts->Dict.keysToArray->Array.forEach(name => counts->Dict.delete(name))
}

/** A setter captured from a render, to call from outside it. */
let setter: ref<option<(int => int) => unit>> = ref(None)
let setFromOutside = f => (setter.contents->Option.getUnsafe)(f)

module Counter = {
  @jsx.component
  let make = (~name: string) => {
    Renders.record(name)
    let (count, setCount) = Hooks.useState(() => 0)
    setter := Some(setCount)
    <button id=name onClick={() => setCount(c => c + 1)}> {TestJsx.int(count)} </button>
  }
}

describe("useState", () => {
  test("starts from init and updates on click", t => {
    let renderer = rendered(<Counter name="c" />)
    t->expect(textOf(renderer, "c"))->Expect.toBe("0")
    TestRenderer.clearOps(renderer)
    TestRenderer.click(renderer, "c")
    t->expect(textOf(renderer, "c"))->Expect.toBe("1")
    t->expect(TestRenderer.ops(renderer))->Expect.toEqual([`text "0" -> "1"`])
  })

  test("the setter keeps its identity", t => {
    let renderer = rendered(<Counter name="c" />)
    let first = setter.contents
    TestRenderer.click(renderer, "c")
    TestRenderer.click(renderer, "c")
    t->expect(setter.contents === first)->Expect.toBe(true)
  })

  test("updates in one act render once, applied in order", t => {
    Renders.reset()
    let renderer = rendered(<Counter name="c" />)
    TestRenderer.act(
      () => {
        setFromOutside(c => c + 1)
        setFromOutside(c => c * 10)
        setFromOutside(c => c + 2)
      },
    )
    t->expect(textOf(renderer, "c"))->Expect.toBe("12")
    t->expect(Renders.get("c"))->Expect.toBe(2)
  })

  testAsync("updates outside act render together in a microtask", async t => {
    Renders.reset()
    let renderer = rendered(<Counter name="c" />)
    setFromOutside(c => c + 1)
    setFromOutside(c => c + 1)
    t->expect(textOf(renderer, "c"))->Expect.toBe("0")
    await Promise.resolve()
    t->expect(textOf(renderer, "c"))->Expect.toBe("2")
    t->expect(Renders.get("c"))->Expect.toBe(2)
  })

  test("setting the same state renders nothing", t => {
    Renders.reset()
    let _ = rendered(<Counter name="c" />)
    TestRenderer.act(() => setFromOutside(c => c))
    t->expect(Renders.get("c"))->Expect.toBe(1)
  })

  test("state is kept while the type and position stay the same, and reset by a new key", t => {
    let renderer = rendered(
      <div id="root">
        <Counter key="1" name="c" />
      </div>,
    )
    TestRenderer.click(renderer, "c")
    TestRenderer.render(
      renderer,
      <div id="root" title="changed">
        <Counter key="1" name="c" />
      </div>,
    )
    t->expect(textOf(renderer, "c"))->Expect.toBe("1")
    TestRenderer.render(
      renderer,
      <div id="root">
        <Counter key="2" name="c" />
      </div>,
    )
    t->expect(textOf(renderer, "c"))->Expect.toBe("0")
  })

  test("setting state while rendering renders again before committing", t => {
    module Converge = {
      @jsx.component
      let make = () => {
        let (count, setCount) = Hooks.useState(() => 0)
        if count < 3 {
          setCount(c => c + 1)
        }
        <span id="n"> {TestJsx.int(count)} </span>
      }
    }
    let renderer = rendered(<Converge />)
    t->expect(textOf(renderer, "n"))->Expect.toBe("3")
    t
    ->expect(TestRenderer.ops(renderer))
    ->Expect.toEqual([`create "3"`, "create span#n", "append span#n to root"])
  })

  test("setting state on every render throws", t => {
    module Forever = {
      @jsx.component
      let make = () => {
        let (_, setCount) = Hooks.useState(() => 0)
        setCount(c => c + 1)
        TestJsx.null
      }
    }
    t->expect(() => rendered(<Forever />))->Expect.toThrow(~message="too many re-renders")
  })

  test("an update to a removed component is ignored", t => {
    let renderer = rendered(<Counter name="c" />)
    TestRenderer.render(renderer, TestJsx.null)
    TestRenderer.act(() => setFromOutside(c => c + 1))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("")
  })
})

type action = Add(int) | Reset

describe("useReducer", () => {
  module Total = {
    @jsx.component
    let make = () => {
      let (total, dispatch) = Hooks.useReducer((total, action) =>
        switch action {
        | Add(n) => total + n
        | Reset => 0
        }
      , 10)
      <button id="total" onClick={() => dispatch(Add(5))}> {TestJsx.int(total)} </button>
    }
  }

  test("dispatches actions to the reducer", t => {
    let renderer = rendered(<Total />)
    TestRenderer.click(renderer, "total")
    TestRenderer.click(renderer, "total")
    t->expect(textOf(renderer, "total"))->Expect.toBe("20")
  })

  test("useReducerWithMapState computes the initial state", t => {
    module Mapped = {
      @jsx.component
      let make = () => {
        let (value, _) = Hooks.useReducerWithMapState((s, _: unit) => s, 4, n => n * n)
        <span id="v"> {TestJsx.int(value)} </span>
      }
    }
    t->expect(textOf(rendered(<Mapped />), "v"))->Expect.toBe("16")
  })
})

describe("useMemo, useCallback and useRef", () => {
  let computations = ref(0)

  module Memo = {
    @jsx.component
    let make = (~a: int, ~b: int) => {
      let sum = Hooks.useMemo1(() => {
        computations := computations.contents + 1
        a + 100
      }, [a])
      let callback = Hooks.useCallback2(() => a + b, (a, b))
      let constant = Hooks.useCallback0(() => 0)
      let box = Hooks.useRef([])
      box.current->Array.push((callback, constant))
      <span id="m" title={Int.toString(Array.length(box.current))}> {TestJsx.int(sum)} </span>
    }
  }

  test("recompute only when their dependencies change", t => {
    computations := 0
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Memo a=1 b=1 />)
    TestRenderer.render(renderer, <Memo a=1 b=2 />)
    TestRenderer.render(renderer, <Memo a=1 b=2 />)
    TestRenderer.render(renderer, <Memo a=2 b=2 />)
    t->expect(textOf(renderer, "m"))->Expect.toBe("102")
    t->expect(computations.contents)->Expect.toBe(2)
    // The ref survived all four renders, collecting each one's callbacks.
    let callbacks = switch TestRenderer.findById(renderer, "m") {
    | Some(node) => TestRenderer.props(node).title
    | None => None
    }
    t->expect(callbacks)->Expect.toEqual(Some("4"))
  })
})

describe("Bailing out", () => {
  module Child = {
    @jsx.component
    let make = () => {
      Renders.record("child")
      <span id="child" />
    }
  }

  module Parent = {
    @jsx.component
    let make = (~children: TestJsx.element) => {
      Renders.record("parent")
      let (count, setCount) = Hooks.useState(() => 0)
      <div id="parent" onClick={() => setCount(c => c + 1)} title={Int.toString(count)}>
        children
      </div>
    }
  }

  test("an update renders only the component that made it", t => {
    Renders.reset()
    let renderer = rendered(
      <div id="root">
        <Counter name="a" />
        <Counter name="b" />
      </div>,
    )
    TestRenderer.click(renderer, "b")
    t->expect((Renders.get("a"), Renders.get("b")))->Expect.toEqual((1, 2))
  })

  test("children passed in from above don't render again when the parent does", t => {
    Renders.reset()
    let renderer = rendered(
      <Parent>
        <Child />
      </Parent>,
    )
    TestRenderer.click(renderer, "parent")
    TestRenderer.click(renderer, "parent")
    t->expect((Renders.get("parent"), Renders.get("child")))->Expect.toEqual((3, 1))
  })

  test("a deep update is reached through components that don't render", t => {
    Renders.reset()
    let renderer = rendered(
      <Parent>
        <div id="wrap">
          <Counter name="deep" />
        </div>
      </Parent>,
    )
    TestRenderer.click(renderer, "deep")
    t->expect(textOf(renderer, "deep"))->Expect.toBe("1")
    t->expect((Renders.get("parent"), Renders.get("deep")))->Expect.toEqual((1, 2))
  })
})

describe("Rules of hooks", () => {
  module Conditional = {
    @jsx.component
    let make = (~first: bool) => {
      if first {
        let _ = Hooks.useState(() => 0)
      }
      let _ = Hooks.useRef(0)
      TestJsx.null
    }
  }

  test("a hook called outside a component throws", t => {
    t
    ->expect(() => Hooks.useState(() => 0))
    ->Expect.toThrow(~message="hooks can only be called while a function component is rendering")
  })

  test("calling hooks in a different order throws", t => {
    let renderer = rendered(<Conditional first=true />)
    t
    ->expect(() => TestRenderer.render(renderer, <Conditional first=false />))
    ->Expect.toThrow(~message="different order")
  })

  test("calling fewer hooks throws", t => {
    module Fewer = {
      @jsx.component
      let make = (~two: bool) => {
        let _ = Hooks.useRef(0)
        if two {
          let _ = Hooks.useRef(0)
        }
        TestJsx.null
      }
    }
    let renderer = rendered(<Fewer two=true />)
    t
    ->expect(() => TestRenderer.render(renderer, <Fewer two=false />))
    ->Expect.toThrow(~message="fewer hooks")
  })

  test("calling more hooks throws", t => {
    module More = {
      @jsx.component
      let make = (~two: bool) => {
        let _ = Hooks.useRef(0)
        if two {
          let _ = Hooks.useRef(0)
        }
        TestJsx.null
      }
    }
    let renderer = rendered(<More two=false />)
    t
    ->expect(() => TestRenderer.render(renderer, <More two=true />))
    ->Expect.toThrow(~message="more hooks")
  })
})

describe("Errors while rendering", () => {
  module Fails = {
    @jsx.component
    let make = (~fail: bool) =>
      fail
        ? JsError.throwWithMessage("render failed")
        : <span id="ok"> {TestJsx.string("ok")} </span>
  }

  test("leave what's on screen alone, and the next render works", t => {
    let renderer = rendered(
      <div id="root">
        <Fails fail=false />
      </div>,
    )
    t
    ->expect(
      () =>
        TestRenderer.render(
          renderer,
          <div id="root" title="new">
            <Fails fail=true />
          </div>,
        ),
    )
    ->Expect.toThrow(~message="render failed")
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div id="root"><span id="ok">ok</span></div>`)
    TestRenderer.render(
      renderer,
      <div id="root" title="new">
        <Fails fail=false />
      </div>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div id="root" title="new"><span id="ok">ok</span></div>`)
  })
})

describe("Hooks: more cases", () => {
  test("setting state while rendering works on updates too (deriving state from props)", t => {
    module Changes = {
      @jsx.component
      let make = (~value: int) => {
        let (previous, setPrevious) = Hooks.useState(() => value)
        let (changes, setChanges) = Hooks.useState(() => 0)
        if value != previous {
          setPrevious(_ => value)
          setChanges(c => c + 1)
        }
        <i id="changes"> {TestJsx.int(changes)} </i>
      }
    }
    let renderer = rendered(<Changes value=1 />)
    [2, 2, 3]->Array.forEach(value => TestRenderer.render(renderer, <Changes value />))
    t->expect(textOf(renderer, "changes"))->Expect.toBe("2")
  })

  test("a flushSync that throws doesn't leave its sync priority behind", t => {
    Renders.reset()
    let renderer = rendered(<Counter name="c" />)
    t
    ->expect(
      () =>
        TestRenderer.flushSync(
          () => {
            setFromOutside(c => c + 1)
            JsError.throwWithMessage("boom")
          },
        ),
    )
    ->Expect.toThrow(~message="boom")
    // A later update gets the default lane, so it renders separately from the sync one.
    setFromOutside(c => c + 10)
    TestRenderer.flushSync(() => ())
    t->expect(textOf(renderer, "c"))->Expect.toBe("11")
    t->expect(Renders.get("c"))->Expect.toBe(3)
  })

  test("TestRenderer.input calls onInput", t => {
    module Field = {
      @jsx.component
      let make = () => {
        let (text, setText) = Hooks.useState(() => "")
        <input id="field" value=text onInput={value => setText(_ => value)} />
      }
    }
    let renderer = rendered(<Field />)
    TestRenderer.input(renderer, "field", "typed")
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<input id="field" value="typed"></input>`)
  })
})

/** How many times each hook variant ran (or, for callbacks, changed identity). */
let runs: dict<int> = Dict.make()
let bump = name => runs->Dict.set(name, runs->Dict.get(name)->Option.getOr(0) + 1)
let callbacks: dict<unknown> = Dict.make()
external toUnknown: 'a => unknown = "%identity"
let seeCallback = (name, f) =>
  if callbacks->Dict.get(name) !== Some(toUnknown(f)) {
    callbacks->Dict.set(name, toUnknown(f))
    bump(name)
  }

module EveryArity = {
  @jsx.component
  let make = (~a: int, ~b: int, ~c: int, ~d: int, ~e: int) => {
    let effect = name =>
      () => {
        bump(name)
        None
      }
    Hooks.useEffect(effect("useEffect"))
    Hooks.useEffect0(effect("useEffect0"))
    Hooks.useEffect1(effect("useEffect1"), [a])
    Hooks.useEffect2(effect("useEffect2"), (a, b))
    Hooks.useEffect3(effect("useEffect3"), (a, b, c))
    Hooks.useEffect4(effect("useEffect4"), (a, b, c, d))
    Hooks.useEffect5(effect("useEffect5"), (a, b, c, d, e))
    Hooks.useLayoutEffect(effect("useLayoutEffect"))
    Hooks.useLayoutEffect0(effect("useLayoutEffect0"))
    Hooks.useLayoutEffect1(effect("useLayoutEffect1"), [a])
    Hooks.useLayoutEffect2(effect("useLayoutEffect2"), (a, b))
    Hooks.useLayoutEffect3(effect("useLayoutEffect3"), (a, b, c))
    Hooks.useLayoutEffect4(effect("useLayoutEffect4"), (a, b, c, d))
    Hooks.useLayoutEffect5(effect("useLayoutEffect5"), (a, b, c, d, e))
    let memo = name => () => bump(name)
    Hooks.useMemo0(memo("useMemo0"))
    Hooks.useMemo1(memo("useMemo1"), [a])
    Hooks.useMemo2(memo("useMemo2"), (a, b))
    Hooks.useMemo3(memo("useMemo3"), (a, b, c))
    Hooks.useMemo4(memo("useMemo4"), (a, b, c, d))
    Hooks.useMemo5(memo("useMemo5"), (a, b, c, d, e))
    seeCallback("useCallback0", Hooks.useCallback0(() => a))
    seeCallback("useCallback1", Hooks.useCallback1(() => a, [a]))
    seeCallback("useCallback2", Hooks.useCallback2(() => a, (a, b)))
    seeCallback("useCallback3", Hooks.useCallback3(() => a, (a, b, c)))
    seeCallback("useCallback4", Hooks.useCallback4(() => a, (a, b, c, d)))
    seeCallback("useCallback5", Hooks.useCallback5(() => a, (a, b, c, d, e)))
    TestJsx.null
  }
}

describe("Hooks: every dependency-list arity", () => {
  test("reruns exactly when one of its own dependencies changes", t => {
    runs->Dict.keysToArray->Array.forEach(key => runs->Dict.delete(key))
    let renderer = TestRenderer.create()
    // Mount; then change only the fifth dependency; then the first.
    TestRenderer.render(renderer, <EveryArity a=0 b=0 c=0 d=0 e=0 />)
    TestRenderer.render(renderer, <EveryArity a=0 b=0 c=0 d=0 e=1 />)
    TestRenderer.render(renderer, <EveryArity a=1 b=0 c=0 d=0 e=1 />)
    let expected = name =>
      switch name->String.slice(~start=String.length(name) - 1) {
      | "0" => 1
      | "5" => 3
      | "1" | "2" | "3" | "4" => 2
      | _ => 3 // no dependencies: every commit
      }
    ["useEffect", "useLayoutEffect", "useMemo", "useCallback"]->Array.forEach(
      family =>
        ["", "0", "1", "2", "3", "4", "5"]->Array.forEach(
          arity => {
            let name = family ++ arity
            if !((family == "useMemo" || family == "useCallback") && arity == "") {
              t->expect((name, runs->Dict.get(name)))->Expect.toEqual((name, Some(expected(name))))
            }
          },
        ),
    )
  })

  test("the layout variants run in the commit, the others after it", t => {
    runs->Dict.keysToArray->Array.forEach(key => runs->Dict.delete(key))
    let renderer = TestRenderer.create()
    TestRenderer.flushSync(
      () => TestRenderer.scheduleRender(renderer, <EveryArity a=0 b=0 c=0 d=0 e=0 />),
    )
    t->expect(runs->Dict.get("useLayoutEffect5"))->Expect.toEqual(Some(1))
    t->expect(runs->Dict.get("useEffect5"))->Expect.toEqual(None)
    TestRenderer.act(() => ())
    t->expect(runs->Dict.get("useEffect5"))->Expect.toEqual(Some(1))
  })
})
