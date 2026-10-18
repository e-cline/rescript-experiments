@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The server entry: an `@e-cline/servy` app (the default export). Pages answer with
`WeftServer.Page.respond` (HTML for a first request, the bare payload for the client's), as do the
frames' routes. The rest are the posts the entrypoints make.

With `WEFT_NOTES_TEST_ROUTES=1` in the environment, `/test/gates/...` routes let a browser test
open the database's gates.
*/

module App = Servy.App
module RequestContext = Servy.RequestContext
module Respond = Servy.Respond
module Route = Servy.Route

@module("virtual:weft/assets") external assets: WeftServer.Page.assets = "default"

external toSignal: EventTypes.abortSignal => Gates.signal = "%identity"

/** What the server does with an error a component throws: a line in the log, and no digest. */
let onError = error => {
  Console.error(`weft_notes: a component failed: ${WeftCore.ErrorBoundary.message(error)}`)
  None
}

let page = (~title, render: Gates.signal => Weft.element): Servy.Handler.t =>
  async ctx =>
    WeftServer.Page.respond(
      ctx.request,
      render(toSignal(ctx.request.signal)),
      ~assets,
      ~title,
      ~onError,
    )

let id = ctx => ctx->RequestContext.paramOrThrow("id")

let field = (json, name) =>
  json
  ->JSON.Decode.object
  ->Option.flatMap(fields => fields->Dict.get(name))
  ->Option.flatMap(JSON.Decode.string)
  ->Option.getOr("")

let body = async ctx =>
  switch await ctx->RequestContext.json(~anyContentType=true) {
  | Ok(json) => json
  | Error(_) => JSON.Null
  }

let noteRoutes = [
  Route.get(list{}, page(~title="Notes", _ => <Pages.NoteList />)),
  Route.get(list{"notes", ":id"}, async ctx =>
    await page(~title="Note", signal => <Pages.NotePage id={id(ctx)} signal />)(ctx)
  ),
  Route.get(list{"notes", ":id", "header"}, async ctx =>
    await page(~title="Note", _ => <Pages.NoteHeader id={id(ctx)} />)(ctx)
  ),
  Route.get(list{"notes", ":id", "comments"}, async ctx =>
    await page(~title="Comments", signal => <Pages.Comments id={id(ctx)} signal />)(ctx)
  ),
  Route.post(list{"notes", ":id"}, async ctx => {
    Db.saveTitle(id(ctx), field(await body(ctx), "title"))
    Respond.empty()
  }),
  Route.post(list{"notes", ":id", "comments"}, async ctx => {
    let json = await body(ctx)
    Db.addComment(id(ctx), ~author=field(json, "author"), ~text=field(json, "text"))->ignore
    Respond.empty()
  }),
  Route.post(list{"notes", ":id", "like"}, async ctx => {
    Db.like(id(ctx))
    Respond.empty()
  }),
]

@val @scope(("process", "env"))
external testRoutesFlag: Nullable.t<string> = "WEFT_NOTES_TEST_ROUTES"

/** For the browser tests: the gates, opened over HTTP. */
let testRoutes = [
  Route.post(list{"test", "gates", "manual"}, async _ => {
    Gates.reset()
    Db.seed()
    Respond.empty()
  }),
  Route.post(list{"test", "gates", "release", ":gate"}, async ctx => {
    Gates.release(ctx->RequestContext.paramOrThrow("gate"))
    Respond.empty()
  }),
]

let app =
  App.build()->App.router(
    testRoutesFlag->Nullable.toOption == Some("1") ? [...noteRoutes, ...testRoutes] : noteRoutes,
  )

let default = app
