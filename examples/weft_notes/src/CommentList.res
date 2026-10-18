@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The comments, which arrive as a promise (the server doesn't wait for them before sending the
rest): read with `Hooks.use`, under a fallback of this component's own.
*/

module Items = {
  @jsx.component
  let make = (~comments: promise<array<Types.comment>>) =>
    <ul id="comment-list">
      {Weft.Hooks.use(comments)
      ->Array.map(comment =>
        <li key=comment.id id={`comment-${comment.id}`}>
          <b> {Weft.Jsx.string(comment.author)} </b>
          {Weft.Jsx.string(": " ++ comment.text)}
        </li>
      )
      ->Weft.Jsx.array}
    </ul>
}

@weft.component({kind: Entrypoint})
let make = (~comments: promise<array<Types.comment>>) =>
  <Weft.Suspense
    fallback={<p id="comment-list-loading"> {Weft.Jsx.string("Loading comments…")} </p>}
  >
    <Items comments />
  </Weft.Suspense>
