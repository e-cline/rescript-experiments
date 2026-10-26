/*** What the harness tests share: the app's root, a `#root` to open pages in, and the checks. */

@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external fileURLToPath: string => string = "fileURLToPath"
@module("node:path") external dirname: string => string = "dirname"

let packageRoot = dirname(dirname(fileURLToPath(importMetaUrl)))

// jsdom has no `<dialog>` methods or Popover API: weft_ui's stand-ins for its overlays.
WeftUi.Testing.installJsdomShims()

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

/** Waits for `page` to hydrate, and whether it did over the server's HTML: every node kept, no warnings. */
let hydratedAsServed = async page => {
  await page->WeftTesting.hydrated
  page->WeftTesting.removedSince(page->WeftTesting.htmlNodes) == [] &&
    page->WeftTesting.warnings == []
}
