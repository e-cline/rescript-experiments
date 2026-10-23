/***
Entrypoints in modules: `Widgets.Toggle`, and `Widgets.Error`, a module ReScript exports as
`$$Error` (it's the name of a JavaScript global), which the client has to find anyway.
*/

module Toggle = {
  @weft.component({kind: Entrypoint})
  let make = (~label: string) => {
    let (open_, setOpen) = Weft.Hooks.useState(() => false)
    <div className="toggle">
      <button onClick={_ => setOpen(open_ => !open_)}> {WeftDom.Jsx.string(label)} </button>
      <p> {WeftDom.Jsx.string(open_ ? "Open" : "Closed")} </p>
    </div>
  }
}

module Error = {
  @weft.component({kind: Entrypoint})
  let make = (~message: string) => <p className="error"> {WeftDom.Jsx.string(message)} </p>
}
