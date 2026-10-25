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

let groupPage = (group: Groups.group) =>
  switch group.slug {
  | "layout" => <LayoutPage group />
  | "text" => <TextPage group />
  | "surfaces" => <SurfacesPage group />
  | "data" => <DataPage group />
  | _ => <ActionsPage group />
  }

let app = App.build()->App.router([
  Route.get(list{}, async ctx =>
    respond(
      ctx,
      ~title="Components",
      <Shell>
        <HomePage />
      </Shell>,
    )
  ),
  Route.get(list{":group"}, async ctx =>
    switch Groups.find(ctx->RequestContext.paramOrThrow("group")) {
    | Some(group) =>
      respond(ctx, ~title=group.title, <Shell current=group.slug> {groupPage(group)} </Shell>)
    | None => respond(ctx, ~title="Not found", <Shell> {WeftDom.Jsx.string("Not found")} </Shell>)
    }
  ),
])

let default = app
