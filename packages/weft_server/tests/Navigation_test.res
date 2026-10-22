@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
`Navigation`: a page fetched again, or another page, rendered over the one on screen, and parts of
it fetched again by themselves (`useRefetchable`), all into a `TestRenderer`, with the server in
the same process (`Support.serve`).
*/

open Vitest
open Support

let shows = TestRenderer.toString
let uid = (renderer, id) => TestRenderer.findById(renderer, id)->Option.map(TestRenderer.uid)
/** The text in the element with `id`. */
let textIn = (renderer, id) =>
  TestRenderer.findById(renderer, id)->Option.map(node =>
    node->TestRenderer.children->Array.map(TestRenderer.text)->Array.join("")
  )

/** A page on `renderer`, its client fetching from `fetch`, started at `url` (rendered at once). */
let start = async (~fetch, ~route, ~url, ~onNavigate=?) => {
  let renderer = TestRenderer.create()
  let client = Decoder.make(~loadModule=Testing.loadModule(makeModules()), ~fetch)
  let navigation = Navigation.make(
    client,
    ~render=element => TestRenderer.scheduleRender(renderer, element),
    ~url,
    ~onNavigate?,
  )
  let element = await roundTrip(~client, route(url))
  navigation->Navigation.show(element)
  await settle()
  (renderer, navigation)
}

// The data the routes render, which tests change "on the server".
let titles = Dict.make()
let comments = Dict.make()
let title = page => titles->Dict.get(page)->Option.getOr(page)
let commentsOf = page => comments->Dict.get(page)->Option.getOr("none")
let reset = () => {
  resetCounts()
  titles->Dict.keysToArray->Array.forEach(key => titles->Dict.delete(key))
  comments->Dict.keysToArray->Array.forEach(key => comments->Dict.delete(key))
}

module CommentList = {
  /** A server component: the comments on `page`, with a counter (an entrypoint) beside them. */
  @jsx.component
  let make = (~page: string) =>
    <ul id="comment-list">
      <li id="text"> {text(commentsOf(page))} </li>
      <Counter label="in-part" />
    </ul>
}

/** The page at `url`: a title, a counter, and the comments, which can be refetched by themselves. */
let route = url =>
  switch url {
  | "/comments/a" | "/comments/b" => <CommentList page={url->String.slice(~start=10)} />
  | "/fails" => <Fails message="the page failed" />
  | _ =>
    let page = url->String.slice(~start=1)
    <section id="page">
      <h1 id="title"> {text(title(page))} </h1>
      <Counter label="outside" />
      <Refetching id="comments" src={`/comments/${page}`}>
        <CommentList page />
      </Refetching>
    </section>
  }

describe("navigating", () => {
  testAsync(
    "renders the new page over the old one, keeping state in the same place, and records the URL",
    async t => {
      reset()
      let navigated = []
      let (fetch, served) = serve(route)
      let (renderer, navigation) = await start(
        ~fetch,
        ~route,
        ~url="/a",
        ~onNavigate=url => navigated->Array.push(url),
      )
      bump("outside")
      let titleNode = uid(renderer, "title")
      await navigation->Navigation.navigate("/b")
      await settle()
      t->expect(textIn(renderer, "title"))->Expect.toEqual(Some("b"))
      t->expect(shows(renderer)->String.includes("outside:1"))->Expect.toBe(true)
      t->expect(uid(renderer, "title"))->Expect.toEqual(titleNode)
      t->expect(navigated)->Expect.toEqual(["/b"])
      t->expect(navigation->Navigation.url)->Expect.toBe("/b")
      t->expect(served->Array.map(request => request.url))->Expect.toEqual(["/b"])
    },
  )

  testAsync("refresh fetches the current page again, without recording a URL", async t => {
    reset()
    let navigated = []
    let (fetch, served) = serve(route)
    let (renderer, navigation) = await start(
      ~fetch,
      ~route,
      ~url="/a",
      ~onNavigate=url => navigated->Array.push(url),
    )
    titles->Dict.set("a", "A, renamed")
    await navigation->Navigation.refresh
    await settle()
    t->expect(shows(renderer)->String.includes("A, renamed"))->Expect.toBe(true)
    t->expect(navigated)->Expect.toEqual([])
    t->expect(served->Array.map(request => request.url))->Expect.toEqual(["/a"])
  })

  testAsync(
    "only the newest of two navigations lands, and the older's stream is cancelled",
    async t => {
      reset()
      let (fetch, served) = serve(~delivery=url => url == "/slow" ? Manual : Immediate, route)
      let (renderer, navigation) = await start(~fetch, ~route, ~url="/a")
      let slow = navigation->Navigation.navigate("/slow")
      await settle()
      let fast = navigation->Navigation.navigate("/fast")
      await fast
      await settle()
      served->Array.forEach(request => Testing.deliverAll(request.pipe))
      await slow
      await settle()
      t->expect(shows(renderer)->String.includes(`id="title">fast`))->Expect.toBe(true)
      t->expect(navigation->Navigation.url)->Expect.toBe("/fast")
      t->expect(Testing.cancelled((served->Array.getUnsafe(0)).pipe))->Expect.toBe(true)
    },
  )

  testAsync(
    "a navigation replacing one still streaming leaves its waiting parts waiting, not failing",
    async t => {
      reset()
      let gate = Deferred.make()
      let route = url =>
        switch url {
        | "/streaming" =>
          <section id="streaming">
            <WeftCore.Suspense fallback=loading>
              <Async ready=gate.promise>
                <b id="late"> {text("late")} </b>
              </Async>
            </WeftCore.Suspense>
          </section>
        | _ => route(url)
        }
      let (fetch, served) = serve(~delivery=url => url == "/next" ? Manual : Immediate, route)
      let (renderer, navigation) = await start(~fetch, ~route, ~url="/a")
      await navigation->Navigation.navigate("/streaming")
      await settle()
      t->expect(shows(renderer)->String.includes(`id="loading"`))->Expect.toBe(true)
      // The next navigation cancels the streaming page's payload while it's still on screen.
      let next = navigation->Navigation.navigate("/next")
      await settle()
      t->expect(Testing.cancelled((served->Array.getUnsafe(0)).pipe))->Expect.toBe(true)
      t->expect(shows(renderer)->String.includes(`id="loading"`))->Expect.toBe(true)
      gate.resolve()
      served->Array.forEach(request => Testing.deliverAll(request.pipe))
      await next
      await settle()
      t->expect(shows(renderer)->String.includes(`id="title">next`))->Expect.toBe(true)
      t->expect(shows(renderer)->String.includes("late"))->Expect.toBe(false)
    },
  )

  testAsync("a page whose root fails rejects, and leaves the screen as it was", async t => {
    reset()
    let (fetch, _) = serve(route)
    let (renderer, navigation) = await start(~fetch, ~route, ~url="/a")
    let before = shows(renderer)
    let failed = switch await navigation->Navigation.navigate("/fails") {
    | () => false
    | exception _ => true
    }
    await settle()
    t->expect(failed)->Expect.toBe(true)
    t->expect(shows(renderer))->Expect.toBe(before)
    t->expect(navigation->Navigation.url)->Expect.toBe("/a")
  })
})

let refetch = src => (refetchers->Dict.getUnsafe(src))()
let pending = renderer =>
  TestRenderer.findById(renderer, "comments")->Option.flatMap(node =>
    (node->TestRenderer.props).title
  )

describe("part of a page, refetched (useRefetchable)", () => {
  testAsync(
    "refetched, patches only its own subtree, and is pending until that has rendered",
    async t => {
      reset()
      let (fetch, served) = serve(
        ~delivery=url => url->String.startsWith("/comments") ? Manual : Immediate,
        route,
      )
      let (renderer, _) = await start(~fetch, ~route, ~url="/a")
      bump("outside")
      bump("in-part")
      let outsideRenders = rendersOf("outside")
      let textNode = uid(renderer, "text")
      comments->Dict.set("a", "two comments")
      let done = refetch("/comments/a")
      await settle()
      t->expect(pending(renderer))->Expect.toEqual(Some("pending"))
      served->Array.forEach(request => Testing.deliverAll(request.pipe))
      await done
      await settle()
      t->expect(pending(renderer))->Expect.toEqual(Some("idle"))
      t->expect(shows(renderer)->String.includes("two comments"))->Expect.toBe(true)
      // The counter in the part kept its state; the one outside didn't render again.
      t->expect(shows(renderer)->String.includes("in-part:1"))->Expect.toBe(true)
      t->expect(shows(renderer)->String.includes("outside:1"))->Expect.toBe(true)
      t->expect(rendersOf("outside"))->Expect.toBe(outsideRenders)
      t->expect(uid(renderer, "text"))->Expect.toEqual(textNode)
      t->expect(served->Array.map(request => request.url))->Expect.toEqual(["/comments/a"])
    },
  )

  testAsync(
    "is replaced by newer children from a refresh, and those by a later refetch",
    async t => {
      reset()
      let (fetch, _) = serve(route)
      let (renderer, navigation) = await start(~fetch, ~route, ~url="/a")
      comments->Dict.set("a", "refetched")
      await refetch("/comments/a")
      await settle()
      t->expect(shows(renderer)->String.includes("refetched"))->Expect.toBe(true)
      comments->Dict.set("a", "refreshed")
      await navigation->Navigation.refresh
      await settle()
      t->expect(shows(renderer)->String.includes("refreshed"))->Expect.toBe(true)
      comments->Dict.set("a", "refetched again")
      await refetch("/comments/a")
      await settle()
      t->expect(shows(renderer)->String.includes("refetched again"))->Expect.toBe(true)
    },
  )

  testAsync("refetched twice, shows only the newer, cancelling the older", async t => {
    reset()
    let calls = ref(0)
    let (fetch, served) = serve(
      ~delivery=url => {
        if url->String.startsWith("/comments") {
          calls := calls.contents + 1
        }
        // The first refetch is held back until the second has rendered.
        url->String.startsWith("/comments") && calls.contents == 1 ? Manual : Immediate
      },
      route,
    )
    let (renderer, _) = await start(~fetch, ~route, ~url="/a")
    comments->Dict.set("a", "older")
    let older = refetch("/comments/a")
    await settle()
    comments->Dict.set("a", "newer")
    await refetch("/comments/a")
    await settle()
    served->Array.forEach(request => Testing.deliverAll(request.pipe))
    await older
    await settle()
    t->expect(shows(renderer)->String.includes("newer"))->Expect.toBe(true)
    t->expect(Testing.cancelled((served->Array.getUnsafe(0)).pipe))->Expect.toBe(true)
  })

  testAsync("a refetch whose root fails rejects, and leaves the part as it was", async t => {
    reset()
    let (fetch, _) = serve(route)
    let (renderer, _) = await start(~fetch, ~route, ~url="/a")
    let before = shows(renderer)
    let failed = switch await (refetchers->Dict.getUnsafe("/comments/a"))(~url="/fails") {
    | () => false
    | exception _ => true
    }
    await settle()
    t->expect(failed)->Expect.toBe(true)
    t->expect(shows(renderer))->Expect.toBe(before)
    t->expect(pending(renderer))->Expect.toEqual(Some("idle"))
  })
})

module TwoParts = {
  @jsx.component
  let make = (~version: string) =>
    <Themed value="dark">
      <Refetching id="left-part" src="/left">
        <p id="left"> {text(`left ${version}`)} </p>
        <ThemeReader id="left-theme" />
      </Refetching>
      <Refetching id="right-part" src="/right">
        <p id="right"> {text(`right ${version}`)} </p>
      </Refetching>
    </Themed>
}

describe("two parts", () => {
  testAsync(
    "are refetched independently, and context from above reaches inside a refetched one",
    async t => {
      reset()
      let version = ref("1")
      let route = url =>
        switch url {
        | "/left" =>
          <>
            <p id="left"> {text(`left ${version.contents}`)} </p>
            <ThemeReader id="left-theme" />
          </>
        | "/right" => <p id="right"> {text(`right ${version.contents}`)} </p>
        | _ => <TwoParts version=version.contents />
        }
      let (fetch, _) = serve(route)
      let (renderer, _) = await start(~fetch, ~route, ~url="/")
      version := "2"
      await refetch("/left")
      await settle()
      let text = id => textIn(renderer, id)
      t->expect(text("left"))->Expect.toEqual(Some("left 2"))
      t->expect(text("right"))->Expect.toEqual(Some("right 1"))
      t->expect(text("left-theme"))->Expect.toEqual(Some("dark"))
    },
  )
})
