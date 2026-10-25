type document
type element
type sheet

@val external document: Nullable.t<document> = "globalThis.document"
@get external head: document => element = "head"
@send external createElement: (document, string) => element = "createElement"
@send external querySelectorAll: (document, string) => array<element> = "querySelectorAll"
@send external getAttribute: (element, string) => Nullable.t<string> = "getAttribute"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external appendChild: (element, element) => unit = "appendChild"
@get external sheet: element => Nullable.t<sheet> = "sheet"
@get external settled: element => Nullable.t<int> = "weftSettled"
@send
external addEventListener: (element, string, unit => unit, {"once": bool}) => unit =
  "addEventListener"
@val external arrayFrom: array<element> => array<element> = "Array.from"

/** A stylesheet's state: shared on `globalThis.__weftCss`, with the page's inline runtime. */
type state = {mutable loaded: bool, mutable promise: promise<unit>}

@val external globalThis: dict<dict<state>> = "globalThis"

let states = () =>
  switch globalThis->Dict.get("__weftCss") {
  | Some(states) => states
  | None =>
    let states = Dict.make()
    globalThis->Dict.set("__weftCss", states)
    states
  }

/** The `<link rel="stylesheet">` in the document for `href`, if there is one. */
let linkOf = (document, href) =>
  document
  ->querySelectorAll(`link[rel="stylesheet"]`)
  ->arrayFrom
  ->Array.find(link => link->getAttribute("href")->Nullable.toOption == Some(href))

/**
The state of `link`'s sheet: loaded if its `sheet` is set, or it has `weftSettled` (the server's
links set it when they load or fail: one that failed has no `sheet`, and fires nothing again), or
once it fires `load` or `error`.
*/
let watch = link => {
  let state = {
    loaded: !Nullable.isNullable(sheet(link)) || !Nullable.isNullable(settled(link)),
    promise: Promise.resolve(),
  }
  if !state.loaded {
    state.promise = Promise.make((resolve, _) => {
      let settle = () => {
        state.loaded = true
        resolve()
      }
      link->addEventListener("load", settle, {"once": true})
      // A sheet that fails shows what waits for it unstyled, rather than never.
      link->addEventListener("error", settle, {"once": true})
    })
  }
  state
}

/** `href`'s state: known, or made from its link (the document's, or a new one in the head). */
let stateOf = (document, href) => {
  let states = states()
  switch states->Dict.get(href) {
  | Some(state) => state
  | None =>
    let link = switch linkOf(document, href) {
    | Some(link) => link
    | None =>
      let link = document->createElement("link")
      link->setAttribute("rel", "stylesheet")
      link->setAttribute("href", href)
      document->head->appendChild(link)
      link
    }
    let state = watch(link)
    states->Dict.set(href, state)
    state
  }
}

let load = href =>
  switch Nullable.toOption(document) {
  | Some(document) => stateOf(document, href).promise
  | None => Promise.resolve()
  }

let isLoaded = href =>
  switch Nullable.toOption(document) {
  | Some(document) => stateOf(document, href).loaded
  | None => true
  }
