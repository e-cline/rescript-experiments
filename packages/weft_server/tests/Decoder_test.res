@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
The client on its own, fed rows written by hand.
*/

open Vitest
open Support

/** A stream the test writes rows into. */
type source = {stream: Streams.t, push: string => unit, end: unit => unit}

let source = () => {
  let controller = ref(None)
  let encoder = Streams.Encoder.make()
  let stream = Streams.make({start: c => controller := Some(c)})
  {
    stream,
    push: text =>
      controller.contents->Option.forEach(c =>
        c->Streams.enqueue(encoder->Streams.Encoder.encode(text))
      ),
    end: () => controller.contents->Option.forEach(Streams.close),
  }
}

let counterRow = `1:E{"id":"test/Entrypoints.res#Counter"}\n`

/** Renders `element` into a new TestRenderer, once everything has arrived. */
let show = async element => {
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, element)
  await settle()
  TestRenderer.toString(renderer)
}

/** Whether `promise` has settled yet. */
let hasSettled = async promise => {
  let settled = ref(false)
  promise
  ->Promise.thenResolve(_ => settled := true)
  ->Promise.catch(_ => {
    settled := true
    Promise.resolve()
  })
  ->ignore
  await Testing.tick()
  settled.contents
}

describe("Client", () => {
  testAsync("decodes host elements, text and entrypoints", async t => {
    let input = source()
    let element = makeClient()->Decoder.fromStream(input.stream)
    input.push(counterRow)
    input.push(`0:J["$","div","k",{"id":"d","children":["$$1",["$","$E1",null,{"label":"a"}]]}]\n`)
    input.end()
    t
    ->expect(await show(await element))
    ->Expect.toBe(
      renderDirectly(
        <div key="k" id="d">
          {text("$1")}
          <Counter label="a" />
        </div>,
      ),
    )
  })

  testAsync(
    "a row waits for the entrypoints it refers to, and each file is loaded once",
    async t => {
      let modules = makeModules()
      modules->Testing.hold
      let input = source()
      let element = makeClient(~modules)->Decoder.fromStream(input.stream)
      input.push(counterRow)
      input.push(`2:E{"id":"test/Entrypoints.res#Probe"}\n`)
      input.push(`0:J["$","div",null,{"children":[["$","$E1",null,{"label":"a"}],["$","$E2",null,{"name":"p","value":1}]]}]\n`)
      input.end()
      t->expect(await hasSettled(element))->Expect.toBe(false)
      modules->Testing.release
      let _ = await element
      t->expect(Testing.loads(modules))->Expect.toEqual(["test/Entrypoints.res"])
    },
  )

  testAsync("rows can refer to rows that haven't arrived, in any order", async t => {
    let input = source()
    let element = makeClient()->Decoder.fromStream(input.stream)
    input.push(`0:J["$","p",null,{"children":["$L2","$L1"]}]\n`)
    let decoded = await element
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <WeftCore.Suspense fallback=loading> decoded </WeftCore.Suspense>)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
    input.push(`2:J"second"\n`)
    input.push(`1:J"first"\n`)
    input.end()
    await settle()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<p>secondfirst</p>")
  })

  testAsync("an error row is thrown where it's used, for an error boundary", async t => {
    let input = source()
    let element = makeClient()->Decoder.fromStream(input.stream)
    input.push(`1:E{"id":"test/Entrypoints.res#Guard"}\n`)
    input.push(`2:X{"message":"server broke","digest":"d1"}\n`)
    input.push(`0:J["$","$E1",null,{"children":"$L2"}]\n`)
    input.end()
    t->expect(await show(await element))->Expect.toBe(`<p id="error">server broke</p>`)
  })

  testAsync("a root that's an error rejects", async t => {
    let input = source()
    let element = makeClient()->Decoder.fromStream(input.stream)
    input.push(`0:X{"message":"no page"}\n`)
    input.end()
    let message = switch await element {
    | _ => None
    | exception JsExn(error) => JsExn.message(error)
    }
    t->expect(message)->Expect.toEqual(Some("no page"))
  })

  testAsync("rows that never arrive fail once the stream ends", async t => {
    let input = source()
    let element = makeClient()->Decoder.fromStream(input.stream)
    input.push(`1:E{"id":"test/Entrypoints.res#Guard"}\n`)
    // As the server writes it: a placeholder only ever appears under a Suspense boundary.
    input.push(`0:J["$","$E1",null,{"children":["$","$S",null,{"fallback":"…","children":"$L7"}]}]\n`)
    input.end()
    t
    ->expect(await show(await element))
    ->Expect.toBe(`<p id="error">WeftServer: the payload ended before its row 7 arrived</p>`)
  })

  testAsync("an entrypoint that can't be loaded fails the rows that use it", async t => {
    let input = source()
    let element = makeClient()->Decoder.fromStream(input.stream)
    input.push(`1:E{"id":"test/Missing.res#"}\n`)
    input.push(`0:J["$","$E1",null,{}]\n`)
    input.end()
    let message = switch await element {
    | _ => None
    | exception JsExn(error) => JsExn.message(error)
    }
    t
    ->expect(message)
    ->Expect.toEqual(
      Some("WeftServer.Testing: no module for test/Missing.res (it isn't in Testing.modules)"),
    )
  })

  testAsync(
    "finds a module named like a JavaScript global under its exported name, $$<name>",
    async t => {
      let modules = Testing.modules([
        (
          "test/Globals.res",
          Testing.module_([
            ("$$Error", Testing.module_([("make", Testing.component(Inner.make))])),
          ]),
        ),
      ])
      let input = source()
      let element = makeClient(~modules)->Decoder.fromStream(input.stream)
      input.push(`1:E{"id":"test/Globals.res#Error"}\n`)
      input.push(`0:J["$","$E1",null,{"label":"x"}]\n`)
      input.end()
      t->expect(await show(await element))->Expect.toBe(`<s id="x">x</s>`)
    },
  )

  testAsync("a promise row is readable by Hooks.use the moment it arrives", async t => {
    let input = source()
    let element = makeClient()->Decoder.fromStream(input.stream)
    input.push(`1:E{"id":"test/Entrypoints.res#Reader"}\n`)
    input.push(`0:J["$","$E1",null,{"id":"r","promise":"$@2"}]\n`)
    input.push(`2:J"ready"\n`)
    input.end()
    let decoded = await element
    await Testing.tick()
    // Rendered once, without a Suspense boundary: it would fail if `use` had to suspend.
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, decoded)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<u id="r">ready</u>`)
  })

  testAsync("a malformed row fails the rows still waiting", async t => {
    let input = source()
    let element = makeClient()->Decoder.fromStream(input.stream)
    input.push(`0:Q{}\n`)
    input.end()
    let failed = switch await element {
    | _ => false
    | exception JsExn(_) => true
    }
    t->expect(failed)->Expect.toBe(true)
  })
})
