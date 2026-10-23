@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
The server renderer on its own: the rows it writes, and when.
*/

open Vitest
open Support

let start = (~onError=?, ~signal=?, element) =>
  Testing.pipe(Render.toStream(element, ~onError?, ~signal?))

let written = pipe => rows(Testing.written(pipe))

/**
Long enough for the renderer to finish what it can and flush it (rows are flushed in a macrotask
after they're written), and for the pipe to pass it on.
*/
let ticks = async () =>
  for _ in 1 to 3 {
    await Testing.tick()
  }

/** The whole payload for `element`, as rows. */
let payload = async (~onError=?, element) => {
  let pipe = start(~onError?, element)
  await Testing.finished(pipe)
  written(pipe)
}

let quietly = _ => None

describe("Render: what it writes", () => {
  testAsync("a tree with nothing to wait for is one row", async t => {
    t
    ->expect(
      await payload(
        <div id="a">
          {text("hi")}
          <b />
        </div>,
      ),
    )
    ->Expect.toEqual([`0:J["$","div",null,{"id":"a","children":["hi",["$","b",null,{}]]}]`])
  })

  testAsync("server components are called, and leave only their output", async t => {
    t
    ->expect(await payload(<Wrap id="w"> {text("inside")} </Wrap>))
    ->Expect.toEqual([`0:J["$","div",null,{"id":"w","children":"inside"}]`])
  })

  testAsync("a keyed server component's output gets its key, in a fragment", async t => {
    t
    ->expect(await payload(<Wrap key="k" id="w"> {text("x")} </Wrap>))
    ->Expect.toEqual([`0:J["$","$F","k",{"children":["$","div",null,{"id":"w","children":"x"}]}]`])
  })

  testAsync(
    "an entrypoint is a reference and its props, with one E row per entrypoint",
    async t => {
      t
      ->expect(
        await payload(
          <div>
            <Counter label="a" />
            <Counter label="b" note="n" />
          </div>,
        ),
      )
      ->Expect.toEqual([
        `1:E{"id":"test/Entrypoints.res#Counter"}`,
        `0:J["$","div",null,{"children":[["$","$E1",null,{"label":"a"}],["$","$E1",null,{"label":"b","note":"n"}]]}]`,
      ])
    },
  )

  testAsync("an entrypoint's element children are rendered on the server", async t => {
    t
    ->expect(
      await payload(
        <Counter label="a">
          <Wrap id="w"> {text("x")} </Wrap>
        </Counter>,
      ),
    )
    ->Expect.toEqual([
      `1:E{"id":"test/Entrypoints.res#Counter"}`,
      `0:J["$","$E1",null,{"label":"a","children":["$","div",null,{"id":"w","children":"x"}]}]`,
    ])
  })

  testAsync("strings starting with $ are escaped, and special numbers written out", async t => {
    t
    ->expect(await payload(<Probe name="p" value=("$5", Float.Constants.nan, -0.0) />))
    ->Expect.toEqual([
      `1:E{"id":"test/Entrypoints.res#Probe"}`,
      `0:J["$","$E1",null,{"name":"p","value":["$$5","$NaN","$-0"]}]`,
    ])
  })
})

describe("Render: waiting and streaming", () => {
  testAsync("outside every Suspense, an async component is waited for, in place", async t => {
    let ready = Deferred.make()
    let pipe = start(
      <div>
        <Async ready=ready.promise> {text("late")} </Async>
      </div>,
    )
    await ticks()
    t->expect(written(pipe))->Expect.toEqual([])
    ready.resolve()
    await Testing.finished(pipe)
    t->expect(written(pipe))->Expect.toEqual([`0:J["$","div",null,{"children":"late"}]`])
  })

  testAsync(
    "under a Suspense, it's a placeholder, and its content follows in its own row",
    async t => {
      let ready = Deferred.make()
      let pipe = start(
        <Weft.Suspense fallback=loading>
          <Async ready=ready.promise> {text("late")} </Async>
        </Weft.Suspense>,
      )
      await ticks()
      t
      ->expect(written(pipe))
      ->Expect.toEqual([
        `0:J["$","$S",null,{"fallback":["$","i",null,{"id":"loading","children":"loading"}],"children":"$L1"}]`,
      ])
      ready.resolve()
      await Testing.finished(pipe)
      t->expect(written(pipe)->Array.get(1))->Expect.toEqual(Some(`1:J"late"`))
    },
  )

  testAsync(
    "two boundaries' rows come in the order their data does, and their work runs at once",
    async t => {
      let (first, second) = (Deferred.make(), Deferred.make())
      let started = []
      module Track = {
        @jsx.component
        let make = (~name: string, ~ready: promise<unit>) => {
          started->Array.push(name)
          <Async ready> {text(name)} </Async>
        }
      }
      let pipe = start(
        <div>
          <Weft.Suspense fallback=loading>
            <Track name="one" ready=first.promise />
          </Weft.Suspense>
          <Weft.Suspense fallback=loading>
            <Track name="two" ready=second.promise />
          </Weft.Suspense>
        </div>,
      )
      await ticks()
      // Both were started before either finished.
      t->expect(started)->Expect.toEqual(["one", "two"])
      second.resolve()
      await ticks()
      first.resolve()
      await Testing.finished(pipe)
      t
      ->expect(written(pipe)->Array.slice(~start=1))
      ->Expect.toEqual([`2:J"two"`, `1:J"one"`])
    },
  )

  testAsync(
    "a component suspended on Hooks.use is called again once its promise settles",
    async t => {
      let data = Deferred.make()
      let pipe = start(<Uses promise=data.promise />)
      await ticks()
      t->expect(written(pipe))->Expect.toEqual([])
      data.resolve("used")
      await Testing.finished(pipe)
      t->expect(written(pipe))->Expect.toEqual([`0:J["$","em",null,{"children":"used"}]`])
    },
  )

  testAsync("a promise prop is a reference, settled by a later row", async t => {
    let data = Deferred.make()
    let pipe = start(<Reader id="r" promise=data.promise />)
    await ticks()
    t
    ->expect(written(pipe))
    ->Expect.toEqual([
      `1:E{"id":"test/Entrypoints.res#Reader"}`,
      `0:J["$","$E1",null,{"id":"r","promise":"$@2"}]`,
    ])
    data.resolve("value")
    await Testing.finished(pipe)
    t->expect(written(pipe)->Array.get(2))->Expect.toEqual(Some(`2:J"value"`))
  })

  testAsync(
    "a component that suspends on a new promise every time gives up, with an error",
    async t => {
      module Forever = {
        @jsx.component
        let make = () =>
          text(Weft.Hooks.use(Promise.resolve("never read")->Promise.thenResolve(x => x)))
      }
      let rows = await payload(
        ~onError=quietly,
        <Weft.Suspense fallback=loading>
          <Forever />
        </Weft.Suspense>,
      )
      t
      ->expect(rows->Array.some(row => row->String.includes("suspended 100 times")))
      ->Expect.toBe(true)
    },
  )
})

describe("Render: errors", () => {
  testAsync(
    "an error under a Suspense is an error row in its place, with onError's digest",
    async t => {
      let seen = []
      let onError = error => {
        seen->Array.push(error)
        Some("digest-1")
      }
      let rows = await payload(
        ~onError,
        <div>
          <Weft.Suspense fallback=loading>
            <Fails message="broken" />
          </Weft.Suspense>
          <b id="fine" />
        </div>,
      )
      t
      ->expect(rows)
      ->Expect.toEqual([
        `1:X{"digest":"digest-1","message":"broken"}`,
        `0:J["$","div",null,{"children":[["$","$S",null,{"fallback":["$","i",null,{"id":"loading","children":"loading"}],"children":"$L1"}],["$","b",null,{"id":"fine"}]]}]`,
      ])
      t->expect(Array.length(seen))->Expect.toBe(1)
    },
  )

  testAsync(
    "so is one straight inside a Suspense, with no server component between (an entrypoint's prop)",
    async t => {
      let rows = await payload(
        ~onError=quietly,
        <div>
          <Weft.Suspense fallback=loading>
            <Probe name="p" value={Map.make()} />
          </Weft.Suspense>
          <b id="fine" />
        </div>,
      )
      t->expect(Array.length(rows))->Expect.toBe(3)
      let errorRow = rows->Array.find(row => row->String.includes(":X"))->Option.getOr("")
      t->expect(errorRow->String.includes("not an instance of a class"))->Expect.toBe(true)
      let root = rows->Array.find(row => row->String.startsWith("0:J"))->Option.getOr("")
      let errorId = errorRow->String.split(":")->Array.getUnsafe(0)
      t->expect(root->String.includes(`"children":"$L${errorId}"`))->Expect.toBe(true)
      t->expect(root->String.includes(`"id":"fine"`))->Expect.toBe(true)
    },
  )

  testAsync("an error outside every boundary fails the root", async t => {
    t
    ->expect(
      await payload(
        ~onError=quietly,
        <div>
          <Fails message="broken" />
        </div>,
      ),
    )
    ->Expect.toEqual([`0:X{"message":"broken"}`])
  })

  let messageOf = async element =>
    switch await payload(~onError=quietly, element) {
    | [row] => row
    | rows => rows->Array.join(" | ")
    }

  testAsync("a function can't be sent, and the message says where it was", async t => {
    let row = await messageOf(
      <div>
        <Probe name="p" value={() => ()} />
      </div>,
    )
    t->expect(row->String.includes("a function can't be sent from the server"))->Expect.toBe(true)
    t->expect(row->String.includes("<div>.children<Support.Probe>.value"))->Expect.toBe(true)
  })

  testAsync("nor an event handler, or a ref, on a host element", async t => {
    let handler = await messageOf(<button onClick={() => ()} />)
    t->expect(handler->String.includes("can't have an event handler"))->Expect.toBe(true)
    let ref = await messageOf(<b ref={Weft.Ref.current: Nullable.null} />)
    t->expect(ref->String.includes("can't have a ref"))->Expect.toBe(true)
  })

  testAsync("nor a class instance, or a cycle", async t => {
    let instance = await messageOf(<Probe name="p" value={Map.make()} />)
    t->expect(instance->String.includes("not an instance of a class"))->Expect.toBe(true)
    let cyclic: array<unknown> = []
    cyclic->Array.push(toUnknown(cyclic))
    let cycle = await messageOf(<Probe name="p" value=cyclic />)
    t->expect(cycle->String.includes("a cycle"))->Expect.toBe(true)
  })

  testAsync("nor a context provider, or an error boundary", async t => {
    let context = Weft.Context.make(0)
    module Provider = {
      let make = Weft.Context.provider(context)
    }
    let provider = await messageOf(<Provider value=1> {text("x")} </Provider>)
    t
    ->expect(provider->String.includes("a context provider can't be rendered on the server"))
    ->Expect.toBe(true)
    let boundary = await messageOf(
      <Weft.ErrorBoundary fallback={(~error as _, ~reset as _) => text("x")}>
        {text("y")}
      </Weft.ErrorBoundary>,
    )
    t
    ->expect(boundary->String.includes("an ErrorBoundary can't be rendered on the server"))
    ->Expect.toBe(true)
  })

  testAsync("a hook that keeps state fails with the server message", async t => {
    module Stateful = {
      @jsx.component
      let make = () => {
        let (count, _) = Weft.Hooks.useState(() => 0)
        TestJsx.int(count)
      }
    }
    let row = await messageOf(<Stateful />)
    t
    ->expect(row->String.includes("can't be used in a component rendered on the server"))
    ->Expect.toBe(true)
  })
})

describe("Render: aborting", () => {
  testAsync("stops pending work: nothing more is written, and nothing called again", async t => {
    let data = Deferred.make()
    let calls = ref(0)
    module Counted = {
      @jsx.component
      let make = (~promise) => {
        calls := calls.contents + 1
        text(Weft.Hooks.use(promise))
      }
    }
    let controller = Streams.Controller.make()
    let pipe = start(
      ~signal=Streams.Controller.signal(controller),
      <Weft.Suspense fallback=loading>
        <Counted promise=data.promise />
      </Weft.Suspense>,
    )
    await ticks()
    let before = written(pipe)
    controller->Streams.Controller.abort
    data.resolve("too late")
    await Testing.finished(pipe)
    await ticks()
    t->expect(written(pipe))->Expect.toEqual(before)
    t->expect(calls.contents)->Expect.toBe(1)
  })

  testAsync("so does the client cancelling the stream", async t => {
    let data = Deferred.make()
    let calls = ref(0)
    module Counted = {
      @jsx.component
      let make = (~promise) => {
        calls := calls.contents + 1
        text(Weft.Hooks.use(promise))
      }
    }
    let stream = Render.toStream(
      <Weft.Suspense fallback=loading>
        <Counted promise=data.promise />
      </Weft.Suspense>,
    )
    let reader = stream->Streams.getReader
    await reader->Streams.Reader.cancel
    data.resolve("too late")
    await ticks()
    await ticks()
    t->expect(calls.contents)->Expect.toBe(1)
  })
})
