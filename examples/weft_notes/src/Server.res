@@weft.server

/***
The server entry: an `@e-cline/servy` app (the default export). Pages answer with
`WeftServer.Page.respond` (HTML for a first request, the bare payload for the client's), as do the
routes of the parts entrypoints fetch again by themselves (the title, the comments). What the
entrypoints change goes through the RPCs in `Api`, answered at `/_weft/rpc/<id>`.

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
  Console.error(`weft_notes: a component failed: ${Weft.ErrorBoundary.message(error)}`)
  None
}

let page = (~title, render: Gates.signal => Weft.Element.t): Servy.Handler.t =>
  async ctx =>
    WeftServer.Page.respond(
      ctx.request,
      render(toSignal(ctx.request.signal)),
      ~assets,
      ~title,
      ~onError,
    )

let id = ctx => ctx->RequestContext.paramOrThrow("id")

let noteRoutes = [
  Route.get(list{}, page(~title="Notes", _ => <Pages.NoteList />)),
  Route.get(list{"notes", ":id"}, async ctx =>
    await page(~title="Note", signal => <Pages.NotePage id={id(ctx)} signal />)(ctx)
  ),
  Route.get(list{"notes", ":id", "title"}, async ctx =>
    await page(~title="Note", _ => <Pages.NoteTitle id={id(ctx)} />)(ctx)
  ),
  Route.get(list{"notes", ":id", "comments"}, async ctx =>
    await page(~title="Comments", signal => <Pages.Comments id={id(ctx)} signal />)(ctx)
  ),
  // The RPCs (`Api`'s, answered by `ApiServer`'s handlers).
  Route.post(list{"_weft", "rpc", ":id"}, async ctx =>
    await ApiServer.router->WeftServer.RpcServer.respond(ctx.request, ~id=id(ctx))
  ),
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
