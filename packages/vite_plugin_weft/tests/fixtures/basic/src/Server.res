/***
The server entry: a fetch handler (the default export), answering a page with HTML that loads the
client's scripts from `virtual:weft/assets`, a payload request with a payload-shaped body, and
`/env` and `/assets.json` with what the tests check.
*/

type assets = {
  scripts: array<string>,
  preloads: array<string>,
  styles: array<string>,
  entrypoints: dict<array<string>>,
}

@module("virtual:weft/assets") external assets: assets = "default"

let handle = async (request: Fetch.request) => {
  let path = request->Fetch.url->Fetch.makeUrl->Fetch.pathname
  switch path {
  | "/env" => Fetch.json({"isDev": Common.Env.isDev})
  | "/assets.json" => Fetch.json(assets)
  | _ =>
    switch request->Fetch.headers->Fetch.header("accept")->Nullable.toOption {
    | Some("text/x-weft-payload") =>
      Fetch.makeResponse(
        `0:J${JSON.stringify(JSON.String(Notes.title(path)))}\n`,
        {headers: dict{"content-type": "text/x-weft-payload"}},
      )
    | _ =>
      let scripts =
        assets.scripts
        ->Array.map(src => `<script type="module" src="${src}"></script>`)
        ->Array.join("")
      Fetch.makeResponse(
        `<!doctype html><html><head>${scripts}</head><body><div id="root"></div>` ++
        `<p>${Notes.title(path)}</p><p id="instance">${Float.toString(Notes.instance)}</p>` ++
        `<p>${WeftCore.Entrypoint.idOf(Likes.make)->Option.getOr("")}</p></body></html>`,
        {headers: dict{"content-type": "text/html; charset=utf-8"}},
      )
    }
  }
}

let default = handle
