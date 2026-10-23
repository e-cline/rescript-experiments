@@jsxConfig({version: 4, module_: "TestJsx"})

open Vitest

module Renders = {
  let counts: dict<int> = Dict.make()
  let record = name => counts->Dict.set(name, counts->Dict.get(name)->Option.getOr(0) + 1)
  let get = name => counts->Dict.get(name)->Option.getOr(0)
  let reset = () => counts->Dict.keysToArray->Array.forEach(name => counts->Dict.delete(name))
}

module Theme = {
  let context = Context.make("light")
  module Provider = {
    let make = Context.provider(context)
  }
}

module ThemeLabel = {
  @weft.component
  let make = (~id: string) => {
    Renders.record(id)
    let theme = Hooks.useContext(Theme.context)
    <span id> {TestJsx.string(theme)} </span>
  }
}

/** Renders `children` (made by its parent) and its own state: it bails out of its children's work. */
module Toggle = {
  @weft.component
  let make = (~id: string, ~children: TestJsx.element) => {
    Renders.record(id)
    let (on, setOn) = Hooks.useState(() => false)
    <div id onClick={() => setOn(on => !on)} title={on ? "on" : "off"}> children </div>
  }
}

/** Holds the theme in state, so a click changes the provider's value. */
module ThemeSwitcher = {
  @weft.component
  let make = (~children: TestJsx.element) => {
    let (theme, setTheme) = Hooks.useState(() => "dark")
    <Theme.Provider value=theme>
      <button id="switch" onClick={() => setTheme(theme => theme == "dark" ? "light" : "dark")} />
      children
    </Theme.Provider>
  }
}

let textOf = (renderer, id) =>
  switch TestRenderer.findById(renderer, id) {
  | Some(node) => TestRenderer.children(node)->Array.map(TestRenderer.text)->Array.join("")
  | None => failwith(`no #${id}`)
  }

describe("Context", () => {
  test("reads the default with no provider above", t => {
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <ThemeLabel id="label" />)
    t->expect(textOf(renderer, "label"))->Expect.toBe("light")
  })

  test("reads the nearest provider's value", t => {
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Theme.Provider value="dark">
        <ThemeLabel id="outer" />
        <Theme.Provider value="blue">
          <ThemeLabel id="inner" />
        </Theme.Provider>
        <ThemeLabel id="after" />
      </Theme.Provider>,
    )
    t
    ->expect((textOf(renderer, "outer"), textOf(renderer, "inner"), textOf(renderer, "after")))
    ->Expect.toEqual(("dark", "blue", "dark"))
  })

  test("a new value reaches consumers past components that don't render", t => {
    Renders.reset()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ThemeSwitcher>
        <Toggle id="toggle">
          <ThemeLabel id="label" />
        </Toggle>
      </ThemeSwitcher>,
    )
    t->expect(textOf(renderer, "label"))->Expect.toBe("dark")
    TestRenderer.click(renderer, "switch")
    t->expect(textOf(renderer, "label"))->Expect.toBe("light")
    // The label rendered again; the toggle in between didn't.
    t->expect((Renders.get("toggle"), Renders.get("label")))->Expect.toEqual((1, 2))
  })

  test("consumers under a provider of the same context keep that provider's value", t => {
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ThemeSwitcher>
        <Theme.Provider value="fixed">
          <ThemeLabel id="label" />
        </Theme.Provider>
      </ThemeSwitcher>,
    )
    TestRenderer.click(renderer, "switch")
    t->expect(textOf(renderer, "label"))->Expect.toBe("fixed")
  })

  test("a component that updates on its own still reads its provider's value", t => {
    module Reader = {
      @weft.component
      let make = () => {
        let theme = Hooks.useContext(Theme.context)
        let (count, setCount) = Hooks.useState(() => 0)
        <button id="reader" onClick={() => setCount(c => c + 1)}>
          {TestJsx.string(`${theme} ${Int.toString(count)}`)}
        </button>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Theme.Provider value="dark">
        <Reader />
      </Theme.Provider>,
    )
    TestRenderer.click(renderer, "reader")
    t->expect(textOf(renderer, "reader"))->Expect.toBe("dark 1")
  })

  test("the same value doesn't render consumers again", t => {
    Renders.reset()
    let renderer = TestRenderer.create()
    let label = <ThemeLabel id="label" />
    TestRenderer.render(renderer, <Theme.Provider value="dark"> label </Theme.Provider>)
    TestRenderer.render(renderer, <Theme.Provider value="dark"> label </Theme.Provider>)
    t->expect(Renders.get("label"))->Expect.toBe(1)
  })
})

module Rounded = {
  @weft.component
  let make = (~value: float) => {
    Renders.record("rounded")
    TestJsx.float(Math.round(value))
  }
  let make = Memo.memoCustomComparison(make, (a, b) => Math.round(a.value) == Math.round(b.value))
}

describe("Memo", () => {
  module Row = {
    @weft.component
    let make = Memo.memo((~label: string) => {
      Renders.record(label)
      <li id=label> {TestJsx.string(label)} </li>
    })
  }

  module CountingRow = {
    @weft.component
    let make = Memo.memo((~label: string) => {
      Renders.record(label)
      let (count, setCount) = Hooks.useState(() => 0)
      <li id=label onClick={() => setCount(c => c + 1)}> {TestJsx.int(count)} </li>
    })
  }

  module Parent = {
    @weft.component
    let make = (~second: string) => {
      let (count, setCount) = Hooks.useState(() => 0)
      <ul id="parent" onClick={() => setCount(c => c + 1)} title={Int.toString(count)}>
        <Row label="first" />
        <Row label=second />
        <CountingRow label="counting" />
      </ul>
    }
  }

  test("skips rendering when the props are equal", t => {
    Renders.reset()
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Parent second="second" />)
    TestRenderer.click(renderer, "parent")
    TestRenderer.click(renderer, "parent")
    t->expect((Renders.get("first"), Renders.get("second")))->Expect.toEqual((1, 1))
  })

  test("renders when the props change", t => {
    Renders.reset()
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Parent second="second" />)
    TestRenderer.render(renderer, <Parent second="changed" />)
    t->expect((Renders.get("first"), Renders.get("changed")))->Expect.toEqual((1, 1))
    t->expect(TestRenderer.findById(renderer, "second"))->Expect.toBe(None)
  })

  test("still renders for its own state", t => {
    Renders.reset()
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Parent second="second" />)
    TestRenderer.click(renderer, "counting")
    t->expect(textOf(renderer, "counting"))->Expect.toBe("1")
    TestRenderer.click(renderer, "parent")
    t->expect(textOf(renderer, "counting"))->Expect.toBe("1")
    t->expect(Renders.get("counting"))->Expect.toBe(2)
  })

  test("still renders for a context it reads", t => {
    module MemoLabel = {
      @weft.component
      let make = Memo.memo(
        (~id: string) => {
          let theme = Hooks.useContext(Theme.context)
          <span id> {TestJsx.string(theme)} </span>
        },
      )
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ThemeSwitcher>
        <MemoLabel id="label" />
      </ThemeSwitcher>,
    )
    TestRenderer.click(renderer, "switch")
    t->expect(textOf(renderer, "label"))->Expect.toBe("light")
  })

  test("memoCustomComparison decides with its function", t => {
    Renders.reset()
    let renderer = TestRenderer.create()
    [1.2, 1.4, 1.6, 1.8, 2.2]->Array.forEach(
      value => TestRenderer.render(renderer, <Rounded value />),
    )
    // 1.2 and 1.4 round to 1, 1.6 and 1.8 (and 2.2) to 2.
    t->expect(Renders.get("rounded"))->Expect.toBe(2)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("2")
  })

  test("shallowEqual compares field by field", t => {
    t->expect(Memo.shallowEqual({"a": 1, "b": "x"}, {"a": 1, "b": "x"}))->Expect.toBe(true)
    t->expect(Memo.shallowEqual({"a": 1, "b": "x"}, {"a": 2, "b": "x"}))->Expect.toBe(false)
    t->expect(Memo.shallowEqual({"a": [1]}, {"a": [1]}))->Expect.toBe(false)
  })
})

module Language = {
  let context = Context.make("en")
  module Provider = {
    let make = Context.provider(context)
  }
}

describe("Context and Memo: more cases", () => {
  test("a component reading two contexts renders again for either", t => {
    Renders.reset()
    module Both = {
      @weft.component
      let make = Memo.memo(
        () => {
          Renders.record("both")
          let theme = Hooks.useContext(Theme.context)
          let language = Hooks.useContext(Language.context)
          <span id="both"> {TestJsx.string(`${theme} ${language}`)} </span>
        },
      )
    }
    let child = <Both />
    let view = (~theme, ~language) =>
      <Theme.Provider value=theme>
        <Language.Provider value=language> child </Language.Provider>
      </Theme.Provider>
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, view(~theme="dark", ~language="en"))
    TestRenderer.render(renderer, view(~theme="dark", ~language="fr"))
    t->expect(textOf(renderer, "both"))->Expect.toBe("dark fr")
    TestRenderer.render(renderer, view(~theme="light", ~language="fr"))
    t->expect(textOf(renderer, "both"))->Expect.toBe("light fr")
    TestRenderer.render(renderer, view(~theme="light", ~language="fr"))
    t->expect(Renders.get("both"))->Expect.toBe(3)
  })

  test("shallowEqual: different sets of fields aren't equal", t => {
    let fields = pairs => Dict.fromArray(pairs)
    t
    ->expect(Memo.shallowEqual(fields([("a", 1)]), fields([("a", 1), ("b", 2)])))
    ->Expect.toBe(false)
    t
    ->expect(Memo.shallowEqual(fields([("a", 1), ("b", 2)]), fields([("a", 1), ("c", 2)])))
    ->Expect.toBe(false)
    let same = {"a": [1]}
    t->expect(Memo.shallowEqual(same, same))->Expect.toBe(true)
  })
})
