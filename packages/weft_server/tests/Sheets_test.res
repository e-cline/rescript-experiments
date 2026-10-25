@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
Stylesheets in the payload: `Render` sends the sheets of what rendered (`C` rows, and rows saying
which they need), the decoder reads past them, and the page links the shell's in its head.
*/

open Vitest
open Support

// Three sheets: `a` uses `base`'s variables, `base` and `cycle` use each other's.
let styles: Render.styles = {
  sheets: dict{
    "waaaaaa": {href: "/a.css", dependencies: ["wbbbbbb"]},
    "wbbbbbb": {href: "/base.css", dependencies: ["wcccccc"]},
    "wcccccc": {href: "/cycle.css", dependencies: ["wbbbbbb"]},
    "wdddddd": {href: "/d.css", dependencies: []},
    "weeeeee": {href: "/counter.css", dependencies: []},
  },
  // `Counter`'s file's code has a sheet of its own.
  entrypoints: dict{"test/Entrypoints.res": ["weeeeee"]},
}

let payload = async element => {
  let pipe = Testing.pipe(Render.toStream(element, ~styles))
  await Testing.finished(pipe)
  rows(Testing.written(pipe))
}

module Pick = {
  /** A server component rendering one of two classes. */
  @weft.component
  let make = (~first: bool) =>
    <p className={first ? "Pick-first_waaaaaa" : "Pick-second_wdddddd"}> {text("x")} </p>
}

describe("Render, with styles", () => {
  testAsync("sends the sheets of the classes rendered, dependencies first, once each", async t => {
    t
    ->expect(
      await payload(
        <div className="hero Card-card_waaaaaa">
          <span className="Card-title_waaaaaa Other-x_wzzzzzz" />
        </div>,
      ),
    )
    ->Expect.toEqual([
      `1:C{"id":"wcccccc","href":"/cycle.css"}`,
      `2:C{"id":"wbbbbbb","href":"/base.css"}`,
      `3:C{"id":"waaaaaa","href":"/a.css"}`,
      `0:J["$C",[1,2,3],["$","div",null,{"className":"hero Card-card_waaaaaa","children":["$","span",null,{"className":"Card-title_waaaaaa Other-x_wzzzzzz"}]}]]`,
    ])
  })

  testAsync("sends only what rendered: a server component's other branch isn't sent", async t => {
    let written = await payload(<Pick first=false />)
    t->expect(written->Array.join("\n"))->Expect.String.toContain("/d.css")
    t->expect(written->Array.join("\n")->String.includes("/a.css"))->Expect.toBe(false)
  })

  testAsync("sends the sheets of classes handed to an entrypoint, and of its own code", async t => {
    let written = await payload(<Probe name="p" value={["x", "Pick-first_waaaaaa"]} />)
    t->expect(written->Array.some(row => row->String.includes("/a.css")))->Expect.toBe(true)
    let counter = await payload(<Counter label="c" />)
    t
    ->expect(counter->Array.filter(row => row->String.includes(":C")))
    ->Expect.toEqual([`2:C{"id":"weeeeee","href":"/counter.css"}`])
  })

  testAsync(
    "a boundary's row says what it needs, and only sheets not yet sent get a row",
    async t => {
      let {promise: ready, resolve} = Promise.withResolvers()
      let pipe = Testing.pipe(
        Render.toStream(
          <div className="A-x_waaaaaa">
            <Weft.Suspense fallback={text("...")}>
              <PageSupport.Later ready>
                <i className="A-y_waaaaaa D-z_wdddddd" />
              </PageSupport.Later>
            </Weft.Suspense>
          </div>,
          ~styles,
        ),
      )
      for _ in 1 to 3 {
        await Testing.tick()
      }
      resolve()
      await Testing.finished(pipe)
      let written = rows(Testing.written(pipe))
      // The root's sheets came with it (rows 2 to 4); the boundary's row (1) reuses them, and has
      // one of its own.
      t
      ->expect(written->Array.slice(~start=4))
      ->Expect.toEqual([
        `5:C{"id":"wdddddd","href":"/d.css"}`,
        `1:J["$C",[2,3,4,5],["$","i",null,{"className":"A-y_waaaaaa D-z_wdddddd"}]]`,
      ])
    },
  )

  testAsync("without styles, sends no sheets, and rows as they were", async t => {
    let pipe = Testing.pipe(Render.toStream(<p className="Card-card_waaaaaa" />))
    await Testing.finished(pipe)
    t
    ->expect(rows(Testing.written(pipe)))
    ->Expect.toEqual([`0:J["$","p",null,{"className":"Card-card_waaaaaa"}]`])
  })
})

describe("Payload", () => {
  test("a row's sheets wrap its value, and unwrap", t => {
    let value = JSON.Encode.string("x")
    t->expect(Payload.withSheets([], value))->Expect.toEqual(value)
    t->expect(Payload.sheetsOf(Payload.withSheets([3, 1], value)))->Expect.toEqual(([3, 1], value))
    // A string that starts with `$` is escaped, so a value can't look like the wrapper.
    t
    ->expect(
      Payload.sheetsOf(JSON.Encode.array([Payload.string("$C"), JSON.Encode.array([]), value])),
    )
    ->Expect.toEqual(([], JSON.Encode.array([JSON.String("$$C"), JSON.Encode.array([]), value])))
  })
})

describe("Decoder, with sheets in the payload", () => {
  testAsync("decodes the elements as without them", async t => {
    let element =
      <div className="Card-card_waaaaaa">
        <Counter label="c" />
      </div>
    let decode = async styles => {
      let modules = Testing.modules([
        (
          "test/Entrypoints.res",
          Testing.module_([
            ("Counter", Testing.module_([("make", Testing.component(Counter.make))])),
          ]),
        ),
      ])
      let client = Decoder.make(~loadModule=Testing.loadModule(modules))
      let decoded = await client->Decoder.fromStream(Render.toStream(element, ~styles?))
      let renderer = Weft.TestRenderer.create()
      Weft.TestRenderer.act(() => Weft.TestRenderer.render(renderer, decoded))
      Weft.TestRenderer.toString(renderer)
    }
    t->expect(await decode(Some(styles)))->Expect.toBe(await decode(None))
  })
})

let pageAssets = (): Page.assets => {
  ...PageSupport.assets(),
  sheets: styles.sheets,
  entrypointSheets: styles.entrypoints,
}

describe("Page, with styles", () => {
  testAsync("links the shell's sheets at the end of its head, after the shell's ready", async t => {
    let {promise: ready, resolve} = Promise.withResolvers()
    let pipe = Testing.pipe(
      Page.toStream(
        <div className="A-x_waaaaaa">
          <Weft.Suspense fallback={text("...")}>
            <PageSupport.Later ready>
              <i className="D-z_wdddddd" />
            </PageSupport.Later>
          </Weft.Suspense>
        </div>,
        ~assets=pageAssets(),
      ),
    )
    // Before the shell: the head's start, and not its end.
    await Testing.tick()
    let before = Testing.written(pipe)
    t->expect(before)->Expect.String.toContain(`<script type="module" async src="/client.js">`)
    t->expect(before->String.includes("</head>"))->Expect.toBe(false)
    for _ in 1 to 5 {
      await Testing.tick()
    }
    let shell = Testing.written(pipe)
    t
    ->expect(shell)
    ->Expect.String.toContain(`<link rel="stylesheet" href="/cycle.css"><link rel="stylesheet" href="/base.css"><link rel="stylesheet" href="/a.css"></head><body><div id="root" data-weft-html="">`)
    resolve()
    await Testing.finished(pipe)
    let page = Testing.written(pipe)
    // The boundary's sheet isn't the shell's: it comes with its rows (loading it is the client's).
    t->expect(page)->Expect.String.toContain(`C{\\"id\\":\\"wdddddd\\"`)
    t->expect(page->String.includes(`<link rel="stylesheet" href="/d.css">`))->Expect.toBe(false)
  })
})
