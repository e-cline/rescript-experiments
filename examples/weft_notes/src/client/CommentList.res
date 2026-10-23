/***
The comments, which arrive as a promise (the server doesn't wait for them before sending the
rest): read with `Hooks.use`, under a fallback of this component's own.
*/

module Items = {
  @weft.component
  let make = (~comments: promise<array<Types.comment>>) =>
    <ul id="comment-list">
      {Weft.Hooks.use(comments)
      ->Array.map(comment =>
        <li key=comment.id id={`comment-${comment.id}`}>
          <b> {WeftDom.Jsx.string(comment.author)} </b>
          {WeftDom.Jsx.string(": " ++ comment.text)}
        </li>
      )
      ->WeftDom.Jsx.array}
    </ul>
}

@weft.component({kind: Entrypoint})
let make = (~comments: promise<array<Types.comment>>) =>
  <Weft.Suspense
    fallback={<p id="comment-list-loading"> {WeftDom.Jsx.string("Loading comments…")} </p>}
  >
    <Items comments />
  </Weft.Suspense>
