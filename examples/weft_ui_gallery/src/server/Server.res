@@weft.server

/***
The server entry: an `@e-cline/servy` app, the fetch handler the Vite plugin runs (its default
export). `/` lists the groups of components, and `/<group>` shows one.
*/

module App = Servy.App
module RequestContext = Servy.RequestContext
module Route = Servy.Route

@module("virtual:weft/assets") external assets: WeftServer.Page.assets = "default"

let respond = (ctx: RequestContext.t, ~title, element) =>
  WeftServer.Page.respond(ctx.request, element, ~assets, ~title=`${title} · weft_ui`)

/** The theme the request's cookie names (the switcher's), or the default. */
let theme = (ctx: RequestContext.t) =>
  ctx.request.headers
  ->Headers.get("cookie")
  ->Null.toOption
  ->Option.flatMap(cookie => Servy.Cookie.parse(cookie)->Map.get(Theme.cookieName))
  ->Option.mapOr("default", Theme.parse)

let groupPage = (group: Groups.group) =>
  switch group.slug {
  | "layout" => <LayoutPage group />
  | "text" => <TextPage group />
  | "surfaces" => <SurfacesPage group />
  | "data" => <DataPage group />
  | "forms" => <FormsPage group />
  | "overlays" => <OverlaysPage group />
  | "disclosure" => <DisclosurePage group />
  | "search" => <SearchPage group />
  | _ => <ActionsPage group />
  }

let app = App.build()->App.router([
  Route.get(list{}, async ctx =>
    respond(
      ctx,
      ~title="Components",
      <Shell theme={theme(ctx)}>
        <HomePage />
      </Shell>,
    )
  ),
  Route.get(list{":group"}, async ctx =>
    switch Groups.find(ctx->RequestContext.paramOrThrow("group")) {
    | Some(group) =>
      respond(
        ctx,
        ~title=group.title,
        <Shell current=group.slug theme={theme(ctx)}> {groupPage(group)} </Shell>,
      )
    | None =>
      respond(
        ctx,
        ~title="Not found",
        <Shell theme={theme(ctx)}> {WeftDom.Jsx.string("Not found")} </Shell>,
      )
    }
  ),
])

let default = app
