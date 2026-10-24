/***
The server entry: a fetch handler (the default export), answering a page with HTML that loads the
client's scripts from `virtual:weft/assets`, a payload request with a payload-shaped body, and
`/env`, `/assets.json`, `/cookies/...` and `/echo` with what the tests check, and `/moved/...` with
redirects.
*/

type assets = {
  scripts: array<string>,
  preloads: array<string>,
  styles: array<string>,
  entrypoints: dict<array<string>>,
}

@module("virtual:weft/assets") external assets: assets = "default"

let redirect = (status, location) =>
  Fetch.makeResponse("", {status, headers: dict{"location": location}})

let handle = async (request: Fetch.request) => {
  let path = request->Fetch.url->Fetch.makeUrl->Fetch.pathname
  switch path {
  | "/env" => Fetch.json({"isDev": Common.Env.isDev})
  | "/assets.json" => Fetch.json(assets)
  | "/cookies/set" =>
    Fetch.makeResponse("", {headers: dict{"set-cookie": "flavour=oat; Path=/; HttpOnly"}})
  | "/cookies/expire" =>
    Fetch.makeResponse("", {headers: dict{"set-cookie": "flavour=; Path=/; Max-Age=0"}})
  | "/cookies/echo" => Fetch.json({"cookie": request->Fetch.headers->Fetch.header("cookie")})
  | "/echo" =>
    Fetch.json({
      "method": request->Fetch.method,
      "body": await request->Fetch.text,
      "contentType": request->Fetch.headers->Fetch.header("content-type"),
    })
  // A page that has moved (a page or a payload request alike), and redirects after it.
  | "/moved" => redirect(302, "/notes/moved")
  | "/moved/twice" => redirect(301, "/moved")
  | "/moved/seen" => redirect(303, "/echo")
  | "/moved/kept" => redirect(307, "/echo")
  | "/moved/away" => redirect(302, "https://elsewhere.example/")
  | "/moved/loop" => redirect(302, "/moved/loop")
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
        `<p>${Weft.Entrypoint.idOf(Likes.make)->Option.getOr("")}</p></body></html>`,
        {headers: dict{"content-type": "text/html; charset=utf-8"}},
      )
    }
  }
}

let default = handle
