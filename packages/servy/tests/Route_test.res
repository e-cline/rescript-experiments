open Vitest

/** A handler that answers with `label`, the parameters it was given, and the rest of the path. */
let echo = (label: string): Handler.t =>
  async ctx => {
    let params =
      ctx.params
      ->Map.entries
      ->Iterator.toArray
      ->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))
      ->Array.map(((name, value)) => `${name}=${value}`)
      ->Array.join(",")
    Respond.text(`${label} {${params}} [${ctx.path->List.toArray->Array.join("/")}]`)
  }

/** What `route` answers a request with, or `None` if it doesn't match. */
let ask = async (~method: string="GET", route: Route.t, path: string): option<string> =>
  switch route->Route.handle(TestSupport.context(~method, path)) {
  | Some(response) => Some(await (await response)->Response.text)
  | None => None
  }

let throws = (f: unit => 'a): bool =>
  switch f() {
  | _ => false
  | exception _ => true
  }

describe("Route", () => {
  testAsync("literal segments match only themselves", async t => {
    let route = Route.get(list{"users", "new"}, echo("new"))
    t->expect(await route->ask("/users/new"))->Expect.toEqual(Some("new {} []"))
    t->expect(await route->ask("/users/new/"))->Expect.toEqual(Some("new {} []"))
    t->expect(await route->ask("/users"))->Expect.toEqual(None)
    t->expect(await route->ask("/users/old"))->Expect.toEqual(None)
    t->expect(await route->ask("/users/new/extra"))->Expect.toEqual(None)
    t->expect(await route->ask("/Users/new"))->Expect.toEqual(None)
  })

  testAsync("the empty path is the root", async t => {
    let route = Route.get(list{}, echo("root"))
    t->expect(await route->ask("/"))->Expect.toEqual(Some("root {} []"))
    t->expect(await route->ask("/x"))->Expect.toEqual(None)
  })

  testAsync("a `:name` segment matches any one segment and binds it", async t => {
    let route = Route.get(list{"users", ":id", "posts", ":post"}, echo("post"))
    t
    ->expect(await route->ask("/users/42/posts/7"))
    ->Expect.toEqual(Some("post {id=42,post=7} []"))
    t->expect(await route->ask("/users/42/posts"))->Expect.toEqual(None)
    t->expect(await route->ask("/users//posts/7"))->Expect.toEqual(None)
  })

  // Matching itself takes segments as they come. An application refuses a
  // path with an encoded slash before it gets here (see App_test).
  testAsync("parameters are decoded, and an encoded slash stays in its segment", async t => {
    let route = Route.get(list{"files", ":name"}, echo("file"))
    t->expect(await route->ask("/files/a%20b"))->Expect.toEqual(Some("file {name=a b} []"))
    t->expect(await route->ask("/files/a%2Fb"))->Expect.toEqual(Some("file {name=a/b} []"))
    t->expect(await route->ask("/files/caf%C3%A9"))->Expect.toEqual(Some("file {name=café} []"))
  })

  testAsync("a literal segment is compared with the decoded path", async t => {
    let route = Route.get(list{"my files"}, echo("files"))
    t->expect(await route->ask("/my%20files"))->Expect.toEqual(Some("files {} []"))
  })

  testAsync("`**` matches the rest of the path, including nothing", async t => {
    let route = Route.get(list{"static", "**"}, echo("static"))
    t
    ->expect(await route->ask("/static/css/site.css"))
    ->Expect.toEqual(Some("static {} [css/site.css]"))
    t->expect(await route->ask("/static"))->Expect.toEqual(Some("static {} []"))
    t->expect(await route->ask("/other/css"))->Expect.toEqual(None)

    let everything = Route.get(list{"**"}, echo("all"))
    t->expect(await everything->ask("/"))->Expect.toEqual(Some("all {} []"))
    t->expect(await everything->ask("/a/b"))->Expect.toEqual(Some("all {} [a/b]"))
  })

  testAsync("literal makes a segment that looks like a parameter or `**` match itself", async t => {
    let me = Route.get(list{"users", Route.literal(":me")}, echo("me"))
    t->expect(await me->ask("/users/:me"))->Expect.toEqual(Some("me {} []"))
    t->expect(await me->ask("/users/42"))->Expect.toEqual(None)

    let stars = Route.get(list{Route.literal("**"), ":id"}, echo("stars"))
    t->expect(await stars->ask("/**/7"))->Expect.toEqual(Some("stars {id=7} []"))
    t->expect(await stars->ask("/a/7"))->Expect.toEqual(None)
    t->expect(await stars->ask("/**/7/more"))->Expect.toEqual(None)

    // And it changes nothing for an ordinary one.
    let plain = Route.get(list{Route.literal("users")}, echo("users"))
    t->expect(await plain->ask("/users"))->Expect.toEqual(Some("users {} []"))
  })

  testAsync("each method has its route, and `any` takes them all", async t => {
    let routes = [
      ("GET", Route.get),
      ("POST", Route.post),
      ("PUT", Route.put),
      ("PATCH", Route.patch),
      ("DELETE", Route.delete),
      ("HEAD", Route.head),
      ("OPTIONS", Route.options),
    ]
    for index in 0 to routes->Array.length - 1 {
      let (method, make) = routes->Array.getUnsafe(index)
      let route = make(list{"x"}, echo(method))
      t->expect(await route->ask(~method, "/x"))->Expect.toEqual(Some(`${method} {} []`))
      let other = method == "GET" ? "POST" : "GET"
      t->expect(await route->ask(~method=other, "/x"))->Expect.toEqual(None)
    }

    let any = Route.any(list{"x"}, echo("any"))
    t->expect(await any->ask(~method="DELETE", "/x"))->Expect.toEqual(Some("any {} []"))
    t->expect(await any->ask(~method="PROPFIND", "/x"))->Expect.toEqual(Some("any {} []"))

    let custom = Route.method(Other("PROPFIND"), list{"x"}, echo("propfind"))
    t->expect(await custom->ask(~method="PROPFIND", "/x"))->Expect.toEqual(Some("propfind {} []"))
    t->expect(await custom->ask("/x"))->Expect.toEqual(None)
  })

  testAsync("none matches nothing", async t => {
    t->expect(await Route.none->ask("/"))->Expect.toEqual(None)
    t->expect(await Route.none->ask("/anything"))->Expect.toEqual(None)
  })

  testAsync("scope puts a prefix on its routes, and tries them in order", async t => {
    let route = Route.scope(
      list{"api", ":version"},
      [],
      [
        Route.get(list{"users"}, echo("users")),
        Route.get(list{"users", ":id"}, echo("user")),
        Route.get(list{":anything"}, echo("fallback")),
        Route.get(list{"users"}, echo("never reached")),
      ],
    )
    t->expect(await route->ask("/api/v1/users"))->Expect.toEqual(Some("users {version=v1} []"))
    t
    ->expect(await route->ask("/api/v2/users/42"))
    ->Expect.toEqual(Some("user {id=42,version=v2} []"))
    t
    ->expect(await route->ask("/api/v1/other"))
    ->Expect.toEqual(Some("fallback {anything=other,version=v1} []"))
    t->expect(await route->ask("/users"))->Expect.toEqual(None)
    t->expect(await route->ask("/api/v1"))->Expect.toEqual(None)
  })

  testAsync("a scope's middleware run only when one of its routes matches", async t => {
    let ran = []
    let mark = (name: string): Middleware.t =>
      next =>
        async ctx => {
          ran->Array.push(name)
          await next(ctx)
        }
    let route = Route.scope(
      list{"admin"},
      [mark("outer"), mark("inner")],
      [Route.get(list{"users"}, echo("users"))],
    )
    t->expect(await route->ask("/admin/nope"))->Expect.toEqual(None)
    t->expect(await route->ask(~method="POST", "/admin/users"))->Expect.toEqual(None)
    t->expect(ran)->Expect.toEqual([])

    t->expect(await route->ask("/admin/users"))->Expect.toEqual(Some("users {} []"))
    t->expect(ran)->Expect.toEqual(["outer", "inner"])
  })

  testAsync("an empty scope, or a scope of none, matches nothing", async t => {
    t->expect(await Route.scope(list{"a"}, [], [])->ask("/a"))->Expect.toEqual(None)
    t
    ->expect(await Route.scope(list{"a"}, [], [Route.none, Route.none])->ask("/a"))
    ->Expect.toEqual(None)
  })

  test("a path that could never work is refused when the route is declared", t => {
    let h = echo("x")
    t->expect(throws(() => Route.get(list{"**", "more"}, h)))->Expect.toBe(true)
    t->expect(throws(() => Route.get(list{"a", ""}, h)))->Expect.toBe(true)
    t->expect(throws(() => Route.get(list{"users/:id"}, h)))->Expect.toBe(true)
    t->expect(throws(() => Route.get(list{"a", ":"}, h)))->Expect.toBe(true)
    t->expect(throws(() => Route.get(list{":id", "x", ":id"}, h)))->Expect.toBe(true)
    // A scope is checked with its prefix.
    t
    ->expect(throws(() => Route.scope(list{":id"}, [], [Route.get(list{":id"}, h)])))
    ->Expect.toBe(true)
    t
    ->expect(throws(() => Route.scope(list{"a", "**"}, [], [Route.get(list{"b"}, h)])))
    ->Expect.toBe(true)
    t->expect(throws(() => Route.get(list{"a", ":id", "**"}, h)))->Expect.toBe(false)
    // A literal has to be a segment a request could have: these never match.
    t->expect(throws(() => Route.get(list{".."}, h)))->Expect.toBe(true)
    t->expect(throws(() => Route.get(list{"a\\b"}, h)))->Expect.toBe(true)
    t->expect(throws(() => Route.get(list{Route.literal("")}, h)))->Expect.toBe(true)
    t->expect(throws(() => Route.get(list{Route.literal("a/b")}, h)))->Expect.toBe(true)
  })
})

// `scope` distributes over alternatives, and nested scopes combine. These
// compare what two routes answer across requests that between them hit every
// alternative and none.
let paths = ["/p/a", "/p/b", "/p/a/1", "/p", "/a", "/p/q/a", "/p/q/b", "/q/a", "/"]

/** What each of `paths` gets from `route`, with the middleware that ran on the way. */
let answers = async (build: (string => Middleware.t) => Route.t): array<option<string>> => {
  let results = []
  for index in 0 to paths->Array.length - 1 {
    let ran = []
    let mark = (name: string): Middleware.t =>
      next =>
        async ctx => {
          ran->Array.push(name)
          await next(ctx)
        }
    let answer = await build(mark)->ask(paths->Array.getUnsafe(index))
    results->Array.push(answer->Option.map(answer => `${answer} via ${ran->Array.join(">")}`))
  }
  results
}

let a = Route.get(list{"a"}, echo("a"))
let b = Route.get(list{"b"}, echo("b"))
let c = Route.get(list{"a", ":n"}, echo("c"))

describe("Route: the laws scope obeys", () => {
  testAsync("scoping a group is scoping each of its routes", async t => {
    let together = await answers(mark => Route.scope(list{"p"}, [mark("m")], [a, b, c]))
    let apart = await answers(
      mark =>
        Route.scope(
          list{},
          [],
          [
            Route.scope(list{"p"}, [mark("m")], [a]),
            Route.scope(list{"p"}, [mark("m")], [b]),
            Route.scope(list{"p"}, [mark("m")], [c]),
          ],
        ),
    )
    t->expect(together)->Expect.toEqual(apart)
    // And it isn't vacuous: some of these matched.
    t->expect(together->Array.getUnsafe(0))->Expect.toEqual(Some("a {} [] via m"))
    t->expect(together->Array.getUnsafe(2))->Expect.toEqual(Some("c {n=1} [] via m"))
    t->expect(together->Array.getUnsafe(3))->Expect.toEqual(None)
  })

  testAsync("nested scopes join their prefixes and their middleware", async t => {
    let nested = await answers(
      mark => Route.scope(list{"p"}, [mark("m")], [Route.scope(list{"q"}, [mark("n")], [a, b])]),
    )
    let flat = await answers(mark => Route.scope(list{"p", "q"}, [mark("m"), mark("n")], [a, b]))
    t->expect(nested)->Expect.toEqual(flat)
    t->expect(nested->Array.getUnsafe(5))->Expect.toEqual(Some("a {} [] via m>n"))
  })

  testAsync("an empty scope changes nothing, and none adds nothing", async t => {
    let plain = await answers(_ => Route.scope(list{"p"}, [], [a, b]))
    let wrapped = await answers(
      _ =>
        Route.scope(
          list{},
          [],
          [Route.scope(list{"p"}, [Middleware.none], [Route.none, a, Route.none, b])],
        ),
    )
    t->expect(wrapped)->Expect.toEqual(plain)
  })
})
