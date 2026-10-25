/*** A file-level entrypoint, using the shared module, and a class of `Theme`'s. */

@weft.component({kind: Entrypoint})
let make = (~count: int) =>
  <span className=Theme.badge> {WeftDom.Jsx.string(Shared.label("likes", count))} </span>
