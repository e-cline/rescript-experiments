@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
Today's date, by the clock where it renders: the server's in its HTML, then the browser's. If the
two say different days (a page opened over midnight), hydrating patches the text, with a warning in
development.
*/

@weft.component({kind: Entrypoint})
let make = () =>
  <span id="today">
    {Weft.Jsx.string(Date.fromTime(Date.now())->Date.toISOString->String.slice(~start=0, ~end=10))}
  </span>
