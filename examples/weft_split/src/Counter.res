/***
A file-level entrypoint (the file's own `make`), with state that survives a refetch.
*/

@weft.component({kind: Entrypoint})
let make = (~label: string) => {
  let (count, setCount) = Weft.Hooks.useState(() => 0)
  <button className="counter" onClick={_ => setCount(count => count + 1)}>
    {WeftDom.Jsx.string(`${label}: ${Int.toString(count)}`)}
  </button>
}
