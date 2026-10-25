%%raw("/** @vitest-environment jsdom */")

/*** Loading stylesheets in a document: once each, adopting the page's own links. */

open Vitest

type element
@val @scope("document") external querySelectorAll: string => array<element> = "querySelectorAll"
@val external arrayFrom: array<element> => array<element> = "Array.from"
let fire: (
  element,
  string,
) => unit = %raw(`(element, type) => element.dispatchEvent(new Event(type))`)
let addLink: (string, bool) => element = %raw(`(href, loaded) => {
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = href;
  // jsdom loads no stylesheets: a sheet that has, as the browser has it, is a link with a sheet.
  if (loaded) Object.defineProperty(link, "sheet", {value: {}});
  document.head.append(link);
  return link;
}`)
let reset: unit => unit = %raw(`() => {
  document.head.innerHTML = "";
  delete globalThis.__weftCss;
}`)

let links = href =>
  querySelectorAll(`link[rel="stylesheet"]`)
  ->arrayFrom
  ->Array.filter(link => (Obj.magic(link)["getAttribute"]("href"): string) == href)

let settled = async promise => {
  let done = ref(false)
  promise->Promise.thenResolve(() => done := true)->ignore
  await Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)
  done.contents
}

describe("Sheets", () => {
  beforeEach(reset)

  testAsync("adds a link to the head, once, and resolves once it loads", async t => {
    let first = WeftCss.Sheets.load("/a.css")
    let second = WeftCss.Sheets.load("/a.css")
    t->expect(links("/a.css")->Array.length)->Expect.toBe(1)
    t->expect(WeftCss.Sheets.isLoaded("/a.css"))->Expect.toBe(false)
    t->expect(await settled(first))->Expect.toBe(false)
    fire(links("/a.css")->Array.getUnsafe(0), "load")
    t->expect(await settled(first))->Expect.toBe(true)
    t->expect(await settled(second))->Expect.toBe(true)
    t->expect(WeftCss.Sheets.isLoaded("/a.css"))->Expect.toBe(true)
  })

  testAsync("counts a sheet that failed as loaded", async t => {
    let loading = WeftCss.Sheets.load("/missing.css")
    fire(links("/missing.css")->Array.getUnsafe(0), "error")
    t->expect(await settled(loading))->Expect.toBe(true)
    t->expect(WeftCss.Sheets.isLoaded("/missing.css"))->Expect.toBe(true)
  })

  testAsync(
    "adopts the page's link: one that has loaded is loaded, one loading is waited for",
    async t => {
      let _ = addLink("/shell.css", true)
      let pending = addLink("/later.css", false)
      t->expect(WeftCss.Sheets.isLoaded("/shell.css"))->Expect.toBe(true)
      t->expect(WeftCss.Sheets.isLoaded("/later.css"))->Expect.toBe(false)
      let loading = WeftCss.Sheets.load("/later.css")
      t
      ->expect((links("/shell.css")->Array.length, links("/later.css")->Array.length))
      ->Expect.toEqual((1, 1))
      fire(pending, "load")
      t->expect(await settled(loading))->Expect.toBe(true)
    },
  )

  test("counts the page's link that has failed already as loaded", t => {
    // As the server writes it: one that failed has no sheet, and fires nothing again.
    let failed = addLink("/failed.css", false)
    Obj.magic(failed)["weftSettled"] = 1
    t->expect(WeftCss.Sheets.isLoaded("/failed.css"))->Expect.toBe(true)
  })

  test("keeps what's loaded on globalThis.__weftCss, for the page's inline runtime", t => {
    let _ = addLink("/shared.css", true)
    let _ = WeftCss.Sheets.load("/shared.css")
    let states: dict<{"loaded": bool}> = %raw(`globalThis.__weftCss`)
    t
    ->expect(states->Dict.get("/shared.css")->Option.map(state => state["loaded"]))
    ->Expect.toEqual(Some(true))
  })
})
