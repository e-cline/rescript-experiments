/***
Today's date, by the clock where it renders: the server's in its HTML, then the browser's. If the
two say different days (a page opened over midnight), hydrating patches the text, with a warning in
development.
*/

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = () =>
  <WeftUi.Text as_=#span tone=#muted size=#sm dataId="today">
    {Jsx.string(Date.fromTime(Date.now())->Date.toISOString->String.slice(~start=0, ~end=10))}
  </WeftUi.Text>
