/***
A file-level entrypoint, using the shared module, and a class of `Theme`'s. `Popover` is loaded only
through `import()`, so it's in a chunk of its own.
*/

let popover = () => import(Popover.view)

@weft.component({kind: Entrypoint})
let make = (~count: int) =>
  <span className=Theme.badge> {WeftDom.Jsx.string(Shared.label("likes", count))} </span>
