/***
The claims this package's types make, checked the only way they can be: by
giving the compiler code that breaks them and seeing that it's turned down.

Each case is a small program compiled against this package as built (so the
workspace has to have been built, as it is before any test task runs). Only
the type checker is run on it.
*/

open Vitest

type spawned = {
  status: Null.t<int>,
  stdout: string,
  stderr: string,
}

type spawnOptions = {
  cwd: string,
  encoding: string,
}

@module("node:child_process")
external spawnSync: (string, array<string>, spawnOptions) => spawned = "spawnSync"
@module("node:fs") external mkdtempSync: string => string = "mkdtempSync"
@module("node:fs") external writeFileSync: (string, string) => unit = "writeFileSync"
@module("node:fs") external rmSync: (string, {"recursive": bool, "force": bool}) => unit = "rmSync"
@module("node:os") external tmpdir: unit => string = "tmpdir"
@module("node:path") external join: (string, string) => string = "join"
@module("node:path") external resolve: (string, string) => string = "resolve"
@val @scope("process") external cwd: unit => string = "cwd"

let package = cwd()

type outcome =
  | Compiles
  | Rejected(string)

/** Type-checks `source` as a module that has done `open Servy`. */
let check = (source: string): outcome => {
  let directory = mkdtempSync(join(tmpdir(), "res-server-types-"))
  writeFileSync(join(directory, "Case.res"), `open Servy\n${source}\n`)
  let result = spawnSync(
    resolve(package, "node_modules/.bin/bsc"),
    [
      "-bs-cmi-only",
      "-I",
      resolve(package, "lib/ocaml"),
      "-I",
      resolve(package, "node_modules/@rescript/webapi/lib/ocaml"),
      "Case.res",
    ],
    {cwd: directory, encoding: "utf8"},
  )
  rmSync(directory, {"recursive": true, "force": true})
  switch result.status->Null.toOption {
  | Some(0) => Compiles
  // Without the colours the compiler puts in its messages.
  | _ => Rejected((result.stdout ++ result.stderr)->String.replaceRegExp(/\x1b\[[0-9;]*m/g, ""))
  }
}

/** Whether `source` is rejected, with a message that mentions `reason`. */
let rejectedFor = (source: string, reason: string): bool =>
  switch check(source) {
  | Rejected(output) => output->String.includes(reason)
  | Compiles => false
  }

let key = `let userKey: Context.Key.t<string> = Context.Key.make(~name="user")`

describe("what the types rule out", () => {
  test("the checks below can pass: a correct program compiles", t => {
    t
    ->expect(
      check(
        `${key}
let attach = (ctx: RequestContext.t): RequestContext.t => ctx->RequestContext.set(userKey, "Ada")
let read = (ctx: RequestContext.t): option<string> => ctx->RequestContext.get(userKey)
let app: App.t = App.build()->App.use(Middleware.provide(userKey, "Ada"))->App.router([
  Route.get(list{"users", ":id"}, async ctx => Respond.text(ctx->RequestContext.paramOrThrow("id"))),
])`,
      ),
    )
    ->Expect.toEqual(Compiles)
  })

  test("a value of the wrong type can't be attached under a key", t => {
    t
    ->expect(
      rejectedFor(
        `${key}
let attach = (ctx: RequestContext.t) => ctx->RequestContext.set(userKey, 42)`,
        "This has type: int",
      ),
    )
    ->Expect.toBe(true)
    t
    ->expect(
      rejectedFor(
        `${key}
let middleware = Middleware.provide(userKey, 42)`,
        "This has type: int",
      ),
    )
    ->Expect.toBe(true)
  })

  test("a value can't be read as a type other than its key's", t => {
    t
    ->expect(
      rejectedFor(
        `${key}
let read = (ctx: RequestContext.t): option<int> => ctx->RequestContext.get(userKey)`,
        "option<string>",
      ),
    )
    ->Expect.toBe(true)
    t
    ->expect(
      rejectedFor(
        `${key}
let read = (ctx: RequestContext.t): int => ctx->RequestContext.getOrThrow(userKey)`,
        "string",
      ),
    )
    ->Expect.toBe(true)
  })

  test("one key can't be used at two types", t => {
    t
    ->expect(
      rejectedFor(
        `let attach = (ctx: RequestContext.t) => {
  let key = Context.Key.make(~name="k")
  ctx->RequestContext.set(key, 42)->RequestContext.set(key, "x")
}`,
        "This has type: string",
      ),
    )
    ->Expect.toBe(true)
  })

  test("a key has to be given its type where it's declared", t => {
    t
    ->expect(rejectedFor(`let key = Context.Key.make(~name="k")`, "cannot be generalized"))
    ->Expect.toBe(true)
  })

  test("a key has to be given a name", t => {
    t
    ->expect(rejectedFor(`let key: Context.Key.t<string> = Context.Key.make()`, "labelled"))
    ->Expect.toBe(true)
  })

  test("a key can't be forged, or a context opened up", t => {
    t->expect(check(`let key: Context.Key.t<int> = {name: "user"}`) != Compiles)->Expect.toBe(true)
    t
    ->expect(check(`let peek = (context: Context.t) => context->Map.size`) != Compiles)
    ->Expect.toBe(true)
  })

  test("an application being built can't be used as one, or skip its handler", t => {
    t
    ->expect(check(`let app: App.t = App.build()->App.use(Middleware.logger())`) != Compiles)
    ->Expect.toBe(true)
    t
    ->expect(check(`let response = App.build()(Request.fromURL("http://x.test/"))`) != Compiles)
    ->Expect.toBe(true)
  })

  test("a handler has to answer with a response, and a middleware with a handler", t => {
    t
    ->expect(check(`let route = Route.get(list{}, async _ctx => "just a string")`) != Compiles)
    ->Expect.toBe(true)
    t
    ->expect(
      check(`let app = App.build()->App.use(async ctx => Respond.text("x"))->App.router([])`) !=
        Compiles,
    )
    ->Expect.toBe(true)
  })

  test("HTML can't be made from a string without saying how", t => {
    t->expect(check(`let page = Respond.html("<p>hi</p>")`) != Compiles)->Expect.toBe(true)
    t
    ->expect(check(`let page = (name: string) => Html.html\`<p>\${name}</p>\``) != Compiles)
    ->Expect.toBe(true)
    t
    ->expect(check(`let page = (name: string) => Html.html\`<p>\${Html.text(name)}</p>\``))
    ->Expect.toEqual(Compiles)
  })

  test("a request body's errors have to be told apart", t => {
    // A `result`, so it can't be used as the value without handling the error.
    t
    ->expect(
      check(`let handler: Handler.t = async ctx => Respond.json(await ctx->RequestContext.json)`) !=
        Compiles,
    )
    ->Expect.toBe(true)
  })
})
