/*** A button that's busy for a moment when pressed, then says it's done: `busy` in use. */

module Ui = WeftUi

@weft.component({kind: Entrypoint})
let make = () => {
  let (state, setState) = Weft.Hooks.useState(() => #idle)
  Weft.Hooks.useEffect1(() =>
    switch state {
    | #saving =>
      let timer = setTimeout(() => setState(_ => #saved), 1500)
      Some(() => clearTimeout(timer))
    | #idle | #saved => None
    }
  , [state])
  <Ui.Stack direction=#row gap=#md align=#center>
    <Ui.Button
      dataId="save-demo"
      variant=#primary
      busy={state == #saving}
      onClick={_ => setState(_ => #saving)}
    >
      {WeftDom.Jsx.string(state == #saving ? "Saving…" : "Save")}
    </Ui.Button>
    <Ui.Text as_=#span tone=#success role="status" dataId="save-demo-status">
      {WeftDom.Jsx.string(state == #saved ? "Saved" : "")}
    </Ui.Text>
  </Ui.Stack>
}
