/***
The server entry: an `@e-cline/servy` application, the fetch handler `@e-cline/weft_vite_plugin`
runs (its default export). Each route answers with `WeftServer.Page.respond`: the HTML page, with
the payload streamed into it, for a first request, and the bare payload for the client's own.
*/

module App = Servy.App
module Route = Servy.Route

@module("virtual:weft/assets") external assets: WeftServer.Page.assets = "default"

let page = (~title, render: unit => Weft.Element.t): Servy.Handler.t =>
  async ctx => WeftServer.Page.respond(ctx.request, render(), ~assets, ~title)

let app =
  App.build()->App.router([
    Route.get(list{}, page(~title="Home", () => <Pages.Home />)),
    Route.get(list{"other"}, page(~title="Other", () => <Pages.Other />)),
  ])

let default = app
