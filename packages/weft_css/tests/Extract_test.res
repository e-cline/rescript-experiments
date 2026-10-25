open Vitest

// What `ppx_weft` writes for two files: `Theme`, with variables and a global, and `Card`, using them.
// Each test records them afresh, as the plugin's runner does when it imports the files.
module Theme = {
  let define = () => {
    let ink = Css.Internal.var_("--Theme-ink_waaaaaa", () => "#1d1b19")
    let line = Css.Internal.var_("--Theme-line_waaaaaa", () => "#e6e0d8")
    Css.Internal.global_("Theme-global0_waaaaaa", ~selector="body", () => {
      margin: Zero,
      color: Var(ink),
    })
    (ink, line)
  }
}

module Card = {
  let define = ((ink, line)) => {
    let fade = Css.Internal.keyframes_("Card-fade_wbbbbbb", () => [
      Css.frame(~at="from", {opacity: 0.}),
    ])
    let card = Css.Internal.class_("Card-card_wbbbbbb", () => {
      border: `1px solid var(${Css.varName(line)})`,
      animationName: fade,
      hover: Css.style({color: Var(ink)}),
    })
    let title = Css.Internal.class_("Card-title_wbbbbbb", ~layer="app.overrides", () => {
      fontWeight: 600,
    })
    (card, title)
  }
}

describe("recording", () => {
  test("gives each file's sheet, base layer first, in declaration order", t => {
    Extract.start()
    let vars = Theme.define()
    let (card, title) = Card.define(vars)
    let sheets = Extract.finish()
    // The calls give their names, as they do at run time.
    t->expect((card, title))->Expect.toEqual(("Card-card_wbbbbbb", "Card-title_wbbbbbb"))
    t
    ->expect(sheets)
    ->Expect.toEqual([
      {
        id: "waaaaaa",
        css: `@layer weft.base, weft.components;
@layer weft.base {
  :where(:root) {
    --Theme-ink_waaaaaa: #1d1b19;
    --Theme-line_waaaaaa: #e6e0d8;
  }
  body {
    margin: 0;
    color: var(--Theme-ink_waaaaaa);
  }
}
`,
        dependencies: [],
      },
      {
        id: "wbbbbbb",
        css: `@layer weft.base, weft.components;
@layer weft.components {
  @keyframes Card-fade_wbbbbbb {
    from {
      opacity: 0;
    }
  }
  .Card-card_wbbbbbb {
    border: 1px solid var(--Theme-line_waaaaaa);
    animation-name: Card-fade_wbbbbbb;
  }
  .Card-card_wbbbbbb:hover {
    color: var(--Theme-ink_waaaaaa);
  }
}
@layer app.overrides {
  .Card-title_wbbbbbb {
    font-weight: 600;
  }
}
`,
        dependencies: ["waaaaaa"],
      },
    ])
  })

  test("records nothing unless started, and nothing after finishing", t => {
    let _ = Theme.define()
    Extract.start()
    t->expect(Extract.finish())->Expect.toEqual([])
    let _ = Theme.define()
    Extract.start()
    t->expect(Extract.finish())->Expect.toEqual([])
  })
})

describe("errors", () => {
  test("a definition that throws is named", t => {
    Extract.start()
    let _ = Css.Internal.class_("Bad-x_wcccccc", () => JsError.throwWithMessage("no"))
    t
    ->expect(() => Extract.finish())
    ->Expect.toThrowError(~message="weft_css: the definition of Bad-x_wcccccc threw: no")
  })

  test("a name registered twice", t => {
    Extract.start()
    let _ = Css.Internal.class_("Twice-x_wcccccc", () => {})
    let _ = Css.Internal.class_("Twice-x_wcccccc", () => {})
    t
    ->expect(() => Extract.finish())
    ->Expect.toThrowError(~message="Twice-x_wcccccc is registered twice")
  })

  test("a name with no sheet id", t => {
    Extract.start()
    let _ = Css.Internal.class_("handmade", () => {})
    t
    ->expect(() => Extract.finish())
    ->Expect.toThrowError(~message="handmade doesn't end in a sheet id")
  })

  test("calling the functions directly, as without ppx_weft", t => {
    t
    ->expect(() => Css.class({display: Flex}))
    ->Expect.toThrowError(~message="this file wasn't compiled with ppx_weft")
    t->expect(() => Css.var("red"))->Expect.toThrowError(~message="Css.var was called directly")
  })
})

describe("helpers", () => {
  test("cx and cxOpt join the names given", t => {
    t->expect(Css.cx(["a", "", "b"]))->Expect.toBe("a b")
    t->expect(Css.cxOpt([Some("a"), None, Some("c")]))->Expect.toBe("a c")
  })

  test("vars makes a style dict of custom properties", t => {
    let accent: Css.var = %raw(`"--Theme-accent_waaaaaa"`)
    t->expect(Css.vars([(accent, "red")]))->Expect.toEqual(dict{"--Theme-accent_waaaaaa": "red"})
  })
})
