/***
An entrypoint only `/other` renders, with a large module (`BigTable`) nothing else uses.
*/

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (~rows: int) => {
  let (shown, setShown) = Weft.Hooks.useState(() => rows)
  <figure className="chart">
    <ul>
      {Array.fromInitializer(~length=shown, i =>
        <li key={Int.toString(i)}> {Jsx.string(BigTable.row(i))} </li>
      )->Jsx.array}
    </ul>
    <button onClick={_ => setShown(shown => shown + 1)}> {Jsx.string("More")} </button>
  </figure>
}
