/*** What the harness tests share: the app's root, a `#root` to open pages in, and the checks. */

@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external fileURLToPath: string => string = "fileURLToPath"
@module("node:path") external dirname: string => string = "dirname"

let packageRoot = dirname(dirname(fileURLToPath(importMetaUrl)))

@val external document: {..} = "document"

/** The document's `#root`, made if there isn't one (the built bootstrap looks for it). */
let rootElement = (): WeftDom.Dom.element =>
  switch document["getElementById"]("root")->Nullable.toOption {
  | Some(root) => root
  | None =>
    let root = document["createElement"]("div")
    root["id"] = "root"
    document["body"]["appendChild"](root)->ignore
    root
  }

let text = (page, selector) => page->WeftTesting.textOf(selector)->Option.getOr("")

/** What the home page shows, once it's all there: every entrypoint but the chart, rendered. */
let homeShows = page =>
  text(page, "h1") == "Home" &&
  text(page, ".motto")->String.includes("Kept on the server") &&
  text(page, ".counter") == "clicks: 0" &&
  text(page, ".toggle button") == "Details" &&
  text(page, ".error") == "Nothing went wrong" &&
  text(page, ".fancy") == "~ fancy ~" &&
  text(page, ".plain") == "plain" &&
  text(page, ".outer .counter") == "inner: 0"

/**
What the other page shows, once it's there. Its counter is where the home page's was, so it's the
same counter, with the same count, given the other page's label (`clicks`, how many it had).
*/
let otherShows = (page, ~clicks) =>
  text(page, "h1") == "Other" &&
  text(page, ".chart li")->String.includes("WEFT_SPLIT_CLIENT_SENTINEL row 0000") &&
  text(page, ".counter") == `other clicks: ${Int.toString(clicks)}`
