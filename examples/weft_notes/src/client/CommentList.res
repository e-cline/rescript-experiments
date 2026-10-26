/***
The comments, which arrive as a promise (the server doesn't wait for them before sending the
rest): read with `Hooks.use`, under a fallback of this component's own.
*/

module Ui = WeftUi

module Items = {
  @weft.component
  let make = (~comments: promise<array<Types.comment>>) =>
    <Ui.List.Root divided=true dataId="comment-list">
      {Weft.Hooks.use(comments)
      ->Array.map(comment =>
        <Ui.List.Item key=comment.id dataId={`comment-${comment.id}`}>
          <Ui.Text as_=#strong weight=#semibold> {WeftDom.Jsx.string(comment.author)} </Ui.Text>
          {WeftDom.Jsx.string(": " ++ comment.text)}
        </Ui.List.Item>
      )
      ->WeftDom.Jsx.array}
    </Ui.List.Root>
}

@weft.component({kind: Entrypoint})
let make = (~comments: promise<array<Types.comment>>) =>
  <Weft.Suspense
    fallback={<Ui.Text dataId="comment-list-loading" tone=#muted italic=true>
      {WeftDom.Jsx.string("Loading comments…")}
    </Ui.Text>}
  >
    <Items comments />
  </Weft.Suspense>
