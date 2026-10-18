@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The server entry: an `@e-cline/servy` application, the fetch handler `@e-cline/vite_plugin_weft`
runs (its default export). Each route answers a payload request (`Accept: text/x-weft-payload`) with
its page's payload, and anything else with the HTML shell, which loads the client.

(Pages streamed into the HTML itself, and navigation, come with `WeftServer.Page` in a later phase.)
*/

module App = Servy.App
module Html = Servy.Html
module RequestContext = Servy.RequestContext
module Respond = Servy.Respond
module Route = Servy.Route

/** `virtual:weft/assets`: what the shell loads. */
type assets = {
  scripts: array<string>,
  preloads: array<string>,
  styles: array<string>,
  entrypoints: dict<array<string>>,
}

@module("virtual:weft/assets") external assets: assets = "default"

external toByteStream: WeftServer.Render.stream => Servy.ByteStream.t = "%identity"

let shell = (~title) => {
  let tags = (urls, tag) => urls->Array.map(tag)->Html.join
  Html.html`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>${Html.text(title)}</title>
    ${assets.styles->tags(url => Html.html`<link rel="stylesheet" href="${Html.url(url)}" />`)}
    ${assets.preloads->tags(url => Html.html`<link rel="modulepreload" href="${Html.url(url)}" />`)}
    ${assets.scripts->tags(url =>
    Html.html`<script type="module" src="${Html.url(url)}"></script>`
  )}
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>`
}

let page = (~title, render: unit => Weft.element): Servy.Handler.t =>
  async ctx =>
    switch ctx->RequestContext.header("accept") {
    | Some(accept) if accept->String.includes(WeftServer.Payload.contentType) =>
      Respond.stream(
        ~contentType=WeftServer.Payload.contentType,
        WeftServer.Render.toStream(render())->toByteStream,
      )
    | _ => Respond.html(shell(~title))
    }

let app =
  App.build()->App.router([
    Route.get(list{}, page(~title="Home", () => <Pages.Home />)),
    Route.get(list{"other"}, page(~title="Other", () => <Pages.Other />)),
  ])

let default = app
