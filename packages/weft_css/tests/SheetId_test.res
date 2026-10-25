open Vitest

describe("ofFileId", () => {
  test("is `w` and six base-36 digits of the file id's hash, as ppx_weft computes it", t => {
    // The same file id gave `_wnscs2w` from the PPX (in phase 0's spike, and its tests).
    t->expect(SheetId.ofFileId("spike-res/src/Button.res"))->Expect.toBe("wnscs2w")
    t
    ->expect(SheetId.ofFileId("@e-cline/weft_shop_example/src/client/AddToCart.res"))
    ->Expect.String.toMatch(/^w[0-9a-z]{6}$/)
  })

  test("differs between files", t => {
    t
    ->expect(SheetId.ofFileId("a/src/A.res") === SheetId.ofFileId("a/src/B.res"))
    ->Expect.toBe(false)
  })

  test("hashes the UTF-8 bytes, as OCaml does", t => {
    // Over UTF-16 code units, this would be `wktz59q`; ppx_weft's tests pin the same value.
    t->expect(SheetId.ofFileId("a/src/Ä.res"))->Expect.toBe("wh00nt5")
  })
})

describe("ofName", () => {
  test("finds the sheet id a name ends in", t => {
    t->expect(SheetId.ofName("AddToCart-Styles-button_wk3f9a2"))->Expect.toEqual(Some("wk3f9a2"))
    t->expect(SheetId.ofName("--Theme-accent_w000000"))->Expect.toEqual(Some("w000000"))
  })

  test("is None for other names", t => {
    t->expect(SheetId.ofName("button"))->Expect.toEqual(None)
    t->expect(SheetId.ofName("a_wk3f9a"))->Expect.toEqual(None)
    t->expect(SheetId.ofName("a_wk3f9a2x"))->Expect.toEqual(None)
    t->expect(SheetId.ofName("a_wK3F9A2"))->Expect.toEqual(None)
  })
})

describe("ofClassList", () => {
  test("gives each sheet once, in order, skipping other classes", t => {
    t
    ->expect(SheetId.ofClassList("  A-x_waaaaaa hero B-y_wbbbbbb  A-z_waaaaaa "))
    ->Expect.toEqual(["waaaaaa", "wbbbbbb"])
    t->expect(SheetId.ofClassList(""))->Expect.toEqual([])
  })
})

describe("inText", () => {
  test("finds the sheets a CSS text's names end in", t => {
    let css = `.A-x_waaaaaa { color: var(--Theme-ink_wbbbbbb); animation-name: Fade-in_wcccccc; }
.A-x_waaaaaa:hover { color: var(--Theme-ink_wbbbbbb); }`
    t->expect(SheetId.inText(css))->Expect.toEqual(["waaaaaa", "wbbbbbb", "wcccccc"])
  })

  test("ignores a longer identifier that only contains one", t => {
    t->expect(SheetId.inText(".x_waaaaaab, .y_waaaaaa-z { }"))->Expect.toEqual([])
  })
})
