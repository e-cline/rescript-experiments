@@jsxConfig({version: 4, module_: "Jsx"})

/***
Hydrating the HTML `Html` renders, in jsdom: `Client.hydrateRoot` adopts the server's nodes (the
same objects before and after), attaches handlers, keeps what the user typed, hydrates boundaries
as the page's runtime swaps their content in, and recovers from mismatches. The fuzz test at the
end streams random trees' HTML into the page in pieces, hydrates at a random point, and checks the
DOM ends up as a client render's, made of the HTML's own elements.
*/

open Vitest
open DomSupport

module Hooks = WeftCore.Hooks

let string = Jsx.string

type console
@val external console: console = "console"
@get external consoleError: console => 'a => unit = "error"
@set external setConsoleError: (console, string => unit) => unit = "error"

/** Runs `f`, collecting what it logs with `console.error`. */
let logging = async (f: unit => promise<'a>) => {
  let original = console->consoleError
  let messages = []
  console->setConsoleError(message => messages->Array.push(message))
  switch await f() {
  | result =>
    console->setConsoleError(original)
    (result, messages)
  | exception error =>
    console->setConsoleError(original)
    throw(error)
  }
}

let deferred = (): (promise<'a>, 'a => unit) => {
  let resolve = ref(_ => ())
  let promise = Promise.make((done, _) => resolve := done)
  (promise, value => resolve.contents(value))
}

let tick = () => Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)

let settle = async () =>
  for _ in 1 to 4 {
    await tick()
    Client.act(() => ())
  }

@get external contentOf: Dom.element => Dom.element = "content"

/** Every node under `container`, in order. */
let nodesOf: Dom.element => array<Dom.node> = %raw(`container => {
  const nodes = [];
  const walker = document.createTreeWalker(container, NodeFilter.SHOW_ALL);
  while (walker.nextNode()) nodes.push(walker.currentNode);
  return nodes;
}`)

let sameNodes: (array<Dom.node>, array<Dom.node>) => bool = %raw(`(a, b) =>
  a.length === b.length && a.every((node, index) => node === b[index])`)

let hydrate = (container, element) => {
  let root = ref(None)
  Client.act(() => root := Some(Client.hydrateRoot(container, element)))
  Option.getUnsafe(root.contents)
}

let find = (container, selector) =>
  switch Nullable.toOption(Dom.querySelector(container, selector)) {
  | Some(element) => element
  | None => failwith(`nothing matches ${selector}`)
  }

external toString: unknown => string = "%identity"
external toUnknown: 'a => unknown = "%identity"
let valueOf = element => toString(Dom.getProperty(element, "value"))

module Counter = {
  @jsx.component
  let make = (~id: string) => {
    let (count, setCount) = Hooks.useState(() => 0)
    <button id onClick={_ => setCount(count => count + 1)}> {Jsx.int(count)} </button>
  }
}

module FailsAfter = {
  /** Fails once `promise` resolves (on the server, in place of `Waits`). */
  @jsx.component
  let make = (~promise: promise<string>) =>
    JsError.throwWithMessage(`failed after ${Hooks.use(promise)}`)
}

module Waits = {
  @jsx.component
  let make = (~promise: promise<string>, ~id: string) => <em id> {string(Hooks.use(promise))} </em>
}

let clicked = (container, selector) => {
  Client.act(() => Dom.click(find(container, selector)))
  Dom.textContent(find(container, selector))
}

describe("hydrating the server's HTML", () => {
  testAsync("adopts every node, the same objects, and attaches handlers", async t => {
    let element =
      <main id="m" className="page" style={dict{"backgroundColor": "red"}}>
        <h1>
          {string("Notes")}
          {string(" & more")}
        </h1>
        <Counter id="c" />
        <WeftCore.Suspense fallback={string("loading")}>
          <p title="t"> {string("in a boundary")} </p>
        </WeftCore.Suspense>
        <input value="v" />
        <label htmlFor="i" hidden=true> {string("label")} </label>
      </main>
    let html = await Html.renderToString(element)
    let container = page(html)
    let before = nodesOf(container)
    let (_, warnings) = await logging(async () => hydrate(container, element))
    t->expect(warnings)->Expect.toEqual([])
    t->expect(sameNodes(before, nodesOf(container)))->Expect.toBe(true)
    t->expect(Dom.innerHTML(container))->Expect.toBe(html)
    t->expect(clicked(container, "#c"))->Expect.toBe("1")
  })

  testAsync("keeps what the user typed or ticked before it hydrated", async t => {
    let element =
      <form>
        <input id="text" value="server" />
        <input id="box" type_="checkbox" checked=false />
        <textarea id="area" value="server text" />
      </form>
    let container = page(await Html.renderToString(element))
    Dom.setProperty(find(container, "#text"), "value", toUnknown("typed"))
    Dom.setProperty(find(container, "#box"), "checked", toUnknown(true))
    let _ = hydrate(container, element)
    t->expect(valueOf(find(container, "#text")))->Expect.toBe("typed")
    t->expect(Dom.getProperty(find(container, "#box"), "checked"))->Expect.toEqual(toUnknown(true))
    // A textarea's text is its value: kept, not removed as a child nobody claimed.
    t->expect(valueOf(find(container, "#area")))->Expect.toBe("server text")
  })

  testAsync("hydrates a boundary once the page's runtime swaps its content in", async t => {
    let (promise, resolve) = deferred()
    let element =
      <div>
        <WeftCore.Suspense fallback={<i> {string("loading")} </i>}>
          <Waits promise id="w" />
          <Counter id="c" />
        </WeftCore.Suspense>
        <Counter id="outside" />
      </div>
    let rendering = Html.render(element)
    let container = page(await rendering->Html.shell)
    let segments = []
    let reader = async () => {
      let stream = rendering->Html.rest
      let decoded = await chunks(stream)
      decoded->Array.forEach(chunk => segments->Array.push(chunk))
    }
    let done = reader()
    let fallback = find(container, "i")
    let (_, warnings) = await logging(async () => hydrate(container, element))
    t->expect(warnings)->Expect.toEqual([])
    // The shell's part works at once; the boundary is still the server's fallback, the same node.
    t->expect(clicked(container, "#outside"))->Expect.toBe("1")
    t->expect(find(container, "i") === fallback)->Expect.toBe(true)
    resolve("arrived")
    await done
    let segment = segments->Array.join("")
    arrive(segment)
    // The segment's content, still in its template.
    let arrived =
      Dom.querySelectorAll(Dom.body(Dom.document), "template")->Array.flatMap(
        template => Dom.querySelectorAll(contentOf(template), "*"),
      )
    // Swapped in by the runtime, but not hydrated until it says so: no handler yet.
    let button =
      arrived->Array.find(element => Dom.getAttribute(element, "id") == Nullable.make("c"))
    t->expect(Option.isSome(button))->Expect.toBe(true)
    run(segment)
    await settle()
    t->expect(Dom.textContent(find(container, "#w")))->Expect.toBe("arrived")
    // The segment's nodes are the ones hydrated.
    t->expect(arrived->Array.includes(find(container, "#c")))->Expect.toBe(true)
    t->expect(clicked(container, "#c"))->Expect.toBe("1")
  })

  testAsync("hydrates a boundary swapped in before the JavaScript ran, with the rest", async t => {
    let (promise, resolve) = deferred()
    let element =
      <WeftCore.Suspense fallback={string("loading")}>
        <Waits promise id="w" />
      </WeftCore.Suspense>
    let rendering = Html.render(element)
    let container = page(await rendering->Html.shell)
    let rest = chunks(rendering->Html.rest)
    resolve("early")
    let segment = (await rest)->Array.join("")
    arrive(segment)
    run(segment)
    let before = nodesOf(container)
    let _ = hydrate(container, element)
    await settle()
    t->expect(sameNodes(before, nodesOf(container)))->Expect.toBe(true)
    t->expect(Dom.textContent(find(container, "#w")))->Expect.toBe("early")
  })

  testAsync(
    "renders a boundary the server failed on the client, before or after hydrating",
    async t => {
      let (promise, resolve) = deferred()
      let element =
        <WeftCore.Suspense fallback={string("loading")}>
          <Waits promise id="w" />
        </WeftCore.Suspense>
      // The server's render fails (another component than the client's would have).
      let rendering = Html.render(
        ~onError=_ => Some("d"),
        <WeftCore.Suspense fallback={string("loading")}>
          <FailsAfter promise />
        </WeftCore.Suspense>,
      )
      let container = page(await rendering->Html.shell)
      let rest = chunks(rendering->Html.rest)
      let _ = hydrate(container, element)
      resolve("x")
      run((await rest)->Array.join(""))
      await settle()
      t->expect(Dom.textContent(find(container, "#w")))->Expect.toBe("x")
    },
  )

  testAsync("warns about attributes that differ, and leaves them", async t => {
    let container = page(`<p title="server">x</p>`)
    let (_, warnings) = await logging(
      async () => hydrate(container, <p title="client"> {string("x")} </p>),
    )
    t
    ->expect(Dom.getAttribute(find(container, "p"), "title"))
    ->Expect.toEqual(Nullable.make("server"))
    t
    ->expect(warnings)
    ->Expect.toEqual([
      `WeftDom: the server's <p> has other attributes than the client's (title: "server", not "client"); they're left as the server wrote them`,
    ])
  })

  testAsync(
    "renders the boundary that doesn't match on the client, and keeps the rest",
    async t => {
      let element =
        <div>
          <h1> {string("kept")} </h1>
          <WeftCore.Suspense fallback={string("loading")}>
            <p> {string("client")} </p>
          </WeftCore.Suspense>
        </div>
      let container = page(`<div><h1>kept</h1><!--$--><span>server</span><!--/$--></div>`)
      let heading = find(container, "h1")
      let (_, warnings) = await logging(async () => hydrate(container, element))
      t->expect(Dom.innerHTML(container))->Expect.toBe("<div><h1>kept</h1><p>client</p></div>")
      t->expect(find(container, "h1") === heading)->Expect.toBe(true)
      t->expect(Array.length(warnings))->Expect.toBe(1)
    },
  )
})

// The fuzz test

module Echo = {
  @jsx.component
  let make = (~children: Jsx.element) => {
    let (title, _) = Hooks.useState(() => "echo")
    <span title> children </span>
  }
}

/** What a random tree's boundaries wait on: each a promise, resolved when the test says. */
type waiting = {promise: promise<string>, resolve: string => unit, label: string}

let rec randomTree = (random, ~depth, ~waits: array<waiting>, ~inBoundary): Jsx.element =>
  switch Random.intBelow(random, depth <= 0 ? 3 : 9) {
  | 0 | 1 => string(Random.pick(random, ["a", "b", "", "c d"]))
  | 2 if inBoundary =>
    let (promise, resolve) = deferred()
    let label = `w${Int.toString(Array.length(waits))}`
    waits->Array.push({promise, resolve, label})
    <Waits promise id=label />
  | 2 => <input value={Random.pick(random, ["", "x"])} />
  | 3 => <Echo> {randomChildren(random, ~depth=depth - 1, ~waits, ~inBoundary)} </Echo>
  | 4 => <> {randomChildren(random, ~depth=depth - 1, ~waits, ~inBoundary)} </>
  | 5 | 6 =>
    <WeftCore.Suspense fallback={<i> {string("loading")} </i>}>
      {randomChildren(random, ~depth=depth - 1, ~waits, ~inBoundary=true)}
    </WeftCore.Suspense>
  | _ =>
    let tag = Random.pick(random, ["div", "section", "b", "ul"])
    let props: DomProps.props = {
      className: ?(Random.intBelow(random, 2) == 0 ? Some("c") : None),
      children: randomChildren(random, ~depth=depth - 1, ~waits, ~inBoundary),
    }
    WeftCore.JsxCore.hostJsx(tag, props)
  }

and randomChildren = (random, ~depth, ~waits, ~inBoundary) => {
  let children = Array.fromInitializer(~length=Random.intBelow(random, 4), _ =>
    randomTree(random, ~depth, ~waits, ~inBoundary)
  )
  WeftCore.JsxCore.markStaticList(children)
  Jsx.array(children)
}

/** Every element under `container`. */
let elementsOf = container => Dom.querySelectorAll(container, "*")

describe("hydrating, fuzzed", () => {
  testAsync(
    "random trees' streamed HTML hydrates into a client render's DOM, of the HTML's elements",
    async t => {
      for seed in 1 to 60 {
        let random = Random.make(Int.toFloat(seed))
        let waits = []
        let element = <div> {randomChildren(random, ~depth=4, ~waits, ~inBoundary=false)} </div>
        let rendering = Html.render(element)
        let container = page(await rendering->Html.shell)
        // Every element the HTML ever puts in the page.
        let fromHtml = Set.fromArray(elementsOf(container))
        let segments = []
        let applied = ref(0)
        let reading = (
          async () => {
            let chunks = await chunks(rendering->Html.rest)
            chunks->Array.forEach(chunk => segments->Array.push(chunk))
          }
        )()
        let apply = () => {
          while applied.contents < Array.length(segments) {
            let segment = segments->Array.getUnsafe(applied.contents)
            arrive(segment)
            Dom.querySelectorAll(Dom.body(Dom.document), "template")->Array.forEach(
              template =>
                Dom.querySelectorAll(contentOf(template), "*")->Array.forEach(
                  element => fromHtml->Set.add(element),
                ),
            )
            run(segment)
            applied := applied.contents + 1
          }
        }
        // Each boundary's content resolved in a random order, with hydration at a random point.
        let order = waits->Array.copy
        for index in Array.length(order) - 1 downto 1 {
          let other = Random.intBelow(random, index + 1)
          let swapped = order->Array.getUnsafe(index)
          order->Array.setUnsafe(index, order->Array.getUnsafe(other))
          order->Array.setUnsafe(other, swapped)
        }
        let hydrateAt = Random.intBelow(random, Array.length(order) + 1)
        let root = ref(None)
        for index in 0 to Array.length(order) {
          if index == hydrateAt {
            root := Some(hydrate(container, element))
          }
          switch order->Array.get(index) {
          | Some(waiting) =>
            waiting.resolve(waiting.label)
            await tick()
            await tick()
            apply()
          | None => ()
          }
          await settle()
        }
        await reading
        apply()
        await settle()
        let expected = clientRender(element)
        await settle()
        t
        ->expect((seed, structure(container)))
        ->Expect.toEqual((seed, structure(expected)))
        let made = elementsOf(container)->Array.filter(element => !(fromHtml->Set.has(element)))
        t->expect((seed, Array.length(made)))->Expect.toEqual((seed, 0))
        ignore(root)
      }
    },
  )
})
