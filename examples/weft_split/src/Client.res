/***
The bootstrap: fetches the current page's payload and renders it into `#root`, and does it again,
in a transition (so entrypoints keep their state), when the dev server says a server file changed.

(The first page's rows arriving in the HTML, and navigation, come with `WeftServer.Page` in a later
phase.)
*/

@module("virtual:weft/client") external loadModule: string => promise<unknown> = "loadModule"

type refresh = {file: string}
@module("virtual:weft/client") external onRefresh: (refresh => unit) => unit => unit = "onRefresh"

@val @scope("location") external pathname: string = "pathname"

let client = WeftServer.Client.make(~loadModule)
let latest = WeftServer.Client.Latest.make()

switch Weft.Dom.document->Weft.Dom.body->Weft.Dom.querySelector("#root")->Nullable.toOption {
| Some(container) =>
  let root = Weft.Client.createRoot(container)
  let show = async () =>
    switch await latest->WeftServer.Client.Latest.fetchElement(client, pathname) {
    | Some(element) => Weft.Transition.start(() => root->Weft.Client.render(element))
    | None => ()
    }
  show()->ignore
  let _stop = onRefresh(_ => show()->ignore)
| None => ()
}
