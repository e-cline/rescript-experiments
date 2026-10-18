/***
Marks a component as an entrypoint: a component that a server renderer doesn't render, but sends to
the client as a reference (its id) and its props, for the client to load and render.

Apps don't call this themselves: `@weft.component({kind: Entrypoint})` (the `ppx_weft` PPX) calls
`mark` with an id naming the component's file and module. The mark is a hidden property on the
component function, so it doesn't change the function or how it renders anywhere else.
*/

/** Marks `component` as the entrypoint `id`. */
let mark: (JsxCore.component<'props>, string) => unit

/** The id `component` was marked with, if it's an entrypoint. */
let idOf: JsxCore.component<'props> => option<string>
