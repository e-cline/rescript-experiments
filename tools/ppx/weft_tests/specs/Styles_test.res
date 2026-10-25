/***
What the PPX does with `weft_css`'s style calls: the compiled fixtures' names and directives, and
the CSS extracted from them, as the Vite plugin will extract it (recording while the files' top
levels run).
*/

open Vitest
open WeftCss

let compiled = name =>
  NodeSupport.readFileSync(NodeSupport.join(NodeSupport.packageRoot, `fixtures/${name}.res.js`))

let lines = name => compiled(name)->String.split("\n")

// The fixtures' sheet ids, as `SheetId` computes them from their file ids.
let stylesId = SheetId.ofFileId("@e-cline/ppx_weft_tests/fixtures/Styles.res")

describe("the compiled style fixtures", () => {
  test("a file with styles starts with `'use weft css'`, after any other directive", t => {
    t->expect(lines("Styles")->Array.get(0))->Expect.toBe(Some("'use weft css'"))
    t
    ->expect(lines("StyledEntrypoint")->Array.slice(~start=0, ~end=2))
    ->Expect.toEqual(["'use weft entrypoint'", "'use weft css'"])
    t
    ->expect(lines("StyledServer")->Array.slice(~start=0, ~end=2))
    ->Expect.toEqual(["'use weft server'", "'use weft css'"])
  })

  test("names are the module path and the binding, then the sheet id the PPX hashed", t => {
    let source = compiled("Styles")
    [
      `"--Styles-ink_${stylesId}"`,
      `"Styles-global0_${stylesId}"`,
      `"Styles-global1_${stylesId}"`,
      `"Styles-fadeIn_${stylesId}"`,
      `"Styles-Card-card_${stylesId}"`,
      `"Styles-Card-Title-title_${stylesId}"`,
      `"Styles-prefixed_${stylesId}"`,
    ]->Array.forEach(name => t->expect(source)->Expect.String.toContain(name))
  })

  test("the PPX's hash is SheetId's, over UTF-8, for a file id that isn't ASCII", t => {
    t
    ->expect(compiled("größe/Sized"))
    ->Expect.String.toContain(
      `"Sized-sized_${SheetId.ofFileId("@e-cline/ppx_weft_tests/fixtures/größe/Sized.res")}"`,
    )
  })

  test("each call keeps its prefix, and its definition is in a function", t => {
    let source = compiled("Styles")
    t
    ->expect(source)
    ->Expect.String.toContain(
      `Css$WeftCss.Internal.class_("Styles-prefixed_${stylesId}", undefined, () => ({`,
    )
    // A fragment is a literal, not a call: nothing runs at the top level for it.
    t->expect(source)->Expect.String.toContain("let base = {\n")
  })
})

describe("extracting the fixtures", () => {
  testAsync("gives the file's sheet, from the definitions the PPX kept", async t => {
    Extract.start()
    // Imported here, while recording, and nowhere else in this test file. (A dynamic import takes
    // a file-level value.)
    let prefixed = await import(Styles.prefixed)
    let sheets = Extract.finish()
    t->expect(prefixed)->Expect.toBe(`Styles-prefixed_${stylesId}`)
    t
    ->expect(sheets)
    ->Expect.toEqual([
      {
        id: stylesId,
        css: `@layer weft.base {
  :root {
    --Styles-ink_${stylesId}: #1d1b19;
  }
  body {
    margin: 0;
    color: var(--Styles-ink_${stylesId});
  }
}
@layer app.reset {
  a {
    color: currentColor;
  }
}
@layer weft.components {
  @keyframes Styles-fadeIn_${stylesId} {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }
  .Styles-Card-card_${stylesId} {
    padding: 10px;
    border-radius: 8px;
    animation-name: Styles-fadeIn_${stylesId};
  }
  .Styles-Card-card_${stylesId}:hover {
    color: var(--Styles-ink_${stylesId});
  }
  .Styles-Card-card_${stylesId} h2 {
    margin: 0;
  }
  .Styles-prefixed_${stylesId} {
    display: grid;
  }
}
@layer app.overrides {
  .Styles-Card-Title-title_${stylesId} {
    font-weight: 600;
  }
}
`,
        dependencies: [],
      },
    ])
  })
})
