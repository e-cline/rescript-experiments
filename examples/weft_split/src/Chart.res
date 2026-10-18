@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
An entrypoint only `/other` renders, with a large module (`BigTable`) nothing else uses.
*/

@weft.component({kind: Entrypoint})
let make = (~rows: int) => {
  let (shown, setShown) = Weft.Hooks.useState(() => rows)
  <figure className="chart">
    <ul>
      {Array.fromInitializer(~length=shown, i =>
        <li key={Int.toString(i)}> {Weft.Jsx.string(BigTable.row(i))} </li>
      )->Weft.Jsx.array}
    </ul>
    <button onClick={_ => setShown(shown => shown + 1)}> {Weft.Jsx.string("More")} </button>
  </figure>
}
